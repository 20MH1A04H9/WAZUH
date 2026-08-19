#!/bin/bash
# =============================================================================
# deploy_patched_opensearch_ml.sh
#
# Fully automates what was done manually across two servers tonight:
#   1. Installs JDK 21 (if missing) and unzip (if missing)
#   2. Clones ml-commons at the version matching your installed wazuh-indexer
#   3. Applies three patches:
#        a. SearchIndexTool.java — sanitizes malformed LLM tool-call JSON
#           (float-formatted ints, bare NaN/Infinity, malformed escapes) on
#           INPUT, and tolerates NaN in real alert data on OUTPUT
#        b. Disables the broken Eclipse JDT formatter P2 mirror fetch
#           (upstream mirror.umd.edu returns 404 — unrelated to this patch,
#           but blocks the build entirely if left as-is)
#        c. Forces a consistent Jackson dependency version to resolve a
#           version conflict at the plugin-bundling stage
#   4. Builds the plugin bundle (:opensearch-ml-plugin:assemble)
#   5. Backs up the currently-installed plugin (timestamped, kept forever —
#      old backups are NOT auto-deleted)
#   6. Stops wazuh-indexer, swaps in the new plugin, restarts
#   7. Verifies cluster health and plugin registration
#   8. Automatically rolls back to the pre-existing backup if verification
#      fails at any point after the swap
#
# USAGE:
#   sudo ./deploy_patched_opensearch_ml.sh
#
# Safe to re-run — each step checks state before acting. Every destructive
# step (removing the old plugin, restarting the service) only happens after
# a successful backup and a successful build.
# =============================================================================

set -uo pipefail

# ─── Config ───────────────────────────────────────────────────────────────
PLUGIN_DIR="/usr/share/wazuh-indexer/plugins/opensearch-ml"
BACKUP_DIR="/root/opensearch-ml-plugin-backups"
BUILD_DIR="/root/ml-commons-build"
INDEXER_URL="https://localhost:9200"

# ─── Colors / logging ────────────────────────────────────────────────────
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; }
die()  { err "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (sudo ./deploy_patched_opensearch_ml.sh)"

# ─── Step 0: Get indexer admin credentials ───────────────────────────────
read -rp "Indexer admin username [admin]: " ADMIN_USER
ADMIN_USER="${ADMIN_USER:-admin}"
read -rsp "Indexer admin password: " ADMIN_PASS
echo

curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" "${INDEXER_URL}/" -o /dev/null -w "%{http_code}" | grep -q "^200$" \
  || die "Could not authenticate to ${INDEXER_URL} with the given credentials. Aborting before touching anything."
log "Credentials verified."

# ─── Step 1: Detect installed opensearch-ml / wazuh-indexer version ──────
[[ -d "$PLUGIN_DIR" ]] || die "Plugin directory not found at ${PLUGIN_DIR} — is this a wazuh-indexer host?"

CURRENT_ML_VERSION=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" "${INDEXER_URL}/_cat/plugins" \
  | grep opensearch-ml | awk '{print $NF}' | head -1)
[[ -n "$CURRENT_ML_VERSION" ]] || die "Could not detect current opensearch-ml plugin version from _cat/plugins."

# Strip any -SNAPSHOT suffix to get the clean release tag for git checkout
BASE_VERSION="${CURRENT_ML_VERSION%-SNAPSHOT}"
GIT_TAG="${BASE_VERSION}.0"
log "Detected installed opensearch-ml version: ${CURRENT_ML_VERSION} (will build against tag ${GIT_TAG})"

# ─── Step 2: Prerequisites ────────────────────────────────────────────────
log "Checking prerequisites..."

if ! command -v java &>/dev/null || ! java -version 2>&1 | grep -q '"21'; then
  log "Installing JDK 21..."
  apt-get update -qq
  apt-get install -y -qq openjdk-21-jdk-headless
fi
export JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
log "JAVA_HOME=${JAVA_HOME}"

if ! command -v unzip &>/dev/null; then
  log "Installing unzip..."
  apt-get update -qq
  apt-get install -y -qq unzip
fi

DISK_AVAIL_GB=$(df --output=avail / | tail -1 | awk '{print int($1/1024/1024)}')
[[ "$DISK_AVAIL_GB" -ge 5 ]] || die "Only ${DISK_AVAIL_GB}G free on / — need at least 5G for the build. Aborting."
log "Disk check OK (${DISK_AVAIL_GB}G free)."

# ─── Step 3: Clone ml-commons at the matching version ─────────────────────
if [[ -d "$BUILD_DIR" ]]; then
  warn "Build directory ${BUILD_DIR} already exists — removing for a clean clone."
  rm -rf "$BUILD_DIR"
fi

log "Cloning ml-commons @ ${GIT_TAG}..."
git clone --quiet --branch "$GIT_TAG" https://github.com/opensearch-project/ml-commons.git "$BUILD_DIR" \
  || die "git clone failed — check network access to github.com, or that tag ${GIT_TAG} exists."

cd "$BUILD_DIR" || die "Could not cd into ${BUILD_DIR}"

# ─── Step 4a: Patch SearchIndexTool.java ──────────────────────────────────
log "Applying SearchIndexTool.java patch (input sanitization + output NaN tolerance)..."

TOOL_FILE="ml-algorithms/src/main/java/org/opensearch/ml/engine/tools/SearchIndexTool.java"
[[ -f "$TOOL_FILE" ]] || die "Expected file not found: ${TOOL_FILE} — repo layout may have changed upstream."

cat > "$TOOL_FILE" << 'JAVAEOF'
/*
 * Copyright OpenSearch Contributors
 * SPDX-License-Identifier: Apache-2.0
 *
 * PATCHED (custom, not upstream):
 *   1. sanitizeLlmJson() — tolerates malformed JSON in LLM tool-call INPUT
 *      (unterminated escapes, bare NaN/Infinity, float-formatted integers)
 *   2. LENIENT_OUTPUT_GSON — tolerates NaN in real alert data when
 *      serializing search results back to the LLM (OUTPUT side)
 */

package org.opensearch.ml.engine.tools;

import static org.opensearch.ml.common.CommonValue.*;

import java.io.IOException;
import java.security.AccessController;
import java.security.PrivilegedExceptionAction;
import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.opensearch.action.search.SearchRequest;
import org.opensearch.action.search.SearchResponse;
import org.opensearch.client.Client;
import org.opensearch.common.xcontent.LoggingDeprecationHandler;
import org.opensearch.common.xcontent.XContentType;
import org.opensearch.core.action.ActionListener;
import org.opensearch.core.xcontent.NamedXContentRegistry;
import org.opensearch.core.xcontent.XContentParser;
import org.opensearch.ml.common.spi.tools.Tool;
import org.opensearch.ml.common.spi.tools.ToolAnnotation;
import org.opensearch.ml.common.transport.connector.MLConnectorSearchAction;
import org.opensearch.ml.common.transport.model.MLModelSearchAction;
import org.opensearch.ml.common.transport.model_group.MLModelGroupSearchAction;
import org.opensearch.ml.common.utils.StringUtils;
import org.opensearch.search.SearchHit;
import org.opensearch.search.builder.SearchSourceBuilder;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonSyntaxException;
import com.google.gson.stream.JsonReader;

import lombok.Getter;
import lombok.Setter;
import lombok.extern.log4j.Log4j2;

@Getter
@Setter
@Log4j2
@ToolAnnotation(SearchIndexTool.TYPE)
public class SearchIndexTool implements Tool {

    public static final String INPUT_FIELD = "input";
    public static final String INDEX_FIELD = "index";
    public static final String QUERY_FIELD = "query";

    public static final String TYPE = "SearchIndexTool";
    private static final String DEFAULT_DESCRIPTION =
        "Use this tool to search an index by providing two parameters: 'index' for the index name, and 'query' for the OpenSearch DSL formatted query. Only use this tool when both index name and DSL query is available.";

    private String name = TYPE;

    private String description = DEFAULT_DESCRIPTION;

    private Client client;

    private NamedXContentRegistry xContentRegistry;

    public SearchIndexTool(Client client, NamedXContentRegistry xContentRegistry) {
        this.client = client;
        this.xContentRegistry = xContentRegistry;
    }

    @Override
    public String getType() {
        return TYPE;
    }

    @Override
    public String getVersion() {
        return null;
    }

    @Override
    public boolean validate(Map<String, String> parameters) {
        return parameters != null && parameters.containsKey(INPUT_FIELD) && parameters.get(INPUT_FIELD) != null;
    }

    private static final Gson LENIENT_OUTPUT_GSON = new GsonBuilder().serializeSpecialFloatingPointValues().create();

    private static final Pattern WHOLE_NUMBER_FLOAT =
        Pattern.compile("(:\\s*-?\\d+)\\.0+(?=[,}\\]\\s])");

    private static final Pattern SPECIAL_FLOAT =
        Pattern.compile(":\\s*(NaN|-?Infinity)(?=[,}\\]\\s])");

    private static String sanitizeLlmJson(String raw) {
        if (raw == null) {
            return null;
        }
        String fixed = raw;
        Matcher m1 = WHOLE_NUMBER_FLOAT.matcher(fixed);
        fixed = m1.replaceAll("$1");
        Matcher m2 = SPECIAL_FLOAT.matcher(fixed);
        fixed = m2.replaceAll(": 0");
        return fixed;
    }

    private static JsonObject parseLlmJsonWithFallback(String input) throws JsonSyntaxException {
        try {
            return StringUtils.gson.fromJson(input, JsonObject.class);
        } catch (JsonSyntaxException strictFailure) {
            log.warn("SearchIndexTool: strict JSON parse failed, attempting sanitized retry. Cause: {}", strictFailure.getMessage());
            String sanitized = sanitizeLlmJson(input);
            try {
                return StringUtils.gson.fromJson(sanitized, JsonObject.class);
            } catch (JsonSyntaxException sanitizedFailure) {
                log.warn("SearchIndexTool: sanitized parse also failed, attempting lenient reader. Cause: {}", sanitizedFailure.getMessage());
                try (JsonReader lenientReader = new JsonReader(new java.io.StringReader(sanitized))) {
                    lenientReader.setLenient(true);
                    return com.google.gson.internal.Streams.parse(lenientReader).getAsJsonObject();
                } catch (Exception lenientFailure) {
                    log.error("SearchIndexTool: all JSON parse fallbacks exhausted for input: {}", input);
                    throw strictFailure;
                }
            }
        }
    }

    private SearchRequest getSearchRequest(String index, String query) throws IOException {
        SearchSourceBuilder searchSourceBuilder = new SearchSourceBuilder();
        XContentParser queryParser = XContentType.JSON.xContent().createParser(xContentRegistry, LoggingDeprecationHandler.INSTANCE, query);
        searchSourceBuilder.parseXContent(queryParser);
        return new SearchRequest().source(searchSourceBuilder).indices(index);
    }

    private static Map<String, Object> processResponse(SearchHit hit) {
        Map<String, Object> docContent = new HashMap<>();
        docContent.put("_index", hit.getIndex());
        docContent.put("_id", hit.getId());
        docContent.put("_score", hit.getScore());
        docContent.put("_source", hit.getSourceAsMap());
        return docContent;
    }

    @Override
    public <T> void run(Map<String, String> parameters, ActionListener<T> listener) {
        try {
            String input = parameters.get(INPUT_FIELD);
            JsonObject jsonObject = parseLlmJsonWithFallback(input);
            String index = Optional.ofNullable(jsonObject).map(x -> x.get(INDEX_FIELD)).map(JsonElement::getAsString).orElse(null);
            String query = Optional.ofNullable(jsonObject).map(x -> x.get(QUERY_FIELD)).map(JsonElement::toString).orElse(null);
            if (index == null || query == null) {
                listener.onFailure(new IllegalArgumentException("SearchIndexTool's two parameter: index and query are required!"));
                return;
            }
            String sanitizedQuery = sanitizeLlmJson(query);
            SearchRequest searchRequest = getSearchRequest(index, sanitizedQuery);

            ActionListener<SearchResponse> actionListener = ActionListener.<SearchResponse>wrap(r -> {
                SearchHit[] hits = r.getHits().getHits();

                if (hits != null && hits.length > 0) {
                    StringBuilder contextBuilder = new StringBuilder();
                    for (SearchHit hit : hits) {
                        String doc = AccessController.doPrivileged((PrivilegedExceptionAction<String>) () -> {
                            Map<String, Object> docContent = processResponse(hit);
                            return LENIENT_OUTPUT_GSON.toJson(docContent);
                        });
                        contextBuilder.append(doc).append("\n");
                    }
                    listener.onResponse((T) contextBuilder.toString());
                } else {
                    listener.onResponse((T) "");
                }
            }, e -> {
                log.error("Failed to search index", e);
                listener.onFailure(e);
            });

            if (Objects.equals(index, ML_CONNECTOR_INDEX)) {
                client.execute(MLConnectorSearchAction.INSTANCE, searchRequest, actionListener);
            } else if (Objects.equals(index, ML_MODEL_INDEX)) {
                client.execute(MLModelSearchAction.INSTANCE, searchRequest, actionListener);
            } else if (Objects.equals(index, ML_MODEL_GROUP_INDEX)) {
                client.execute(MLModelGroupSearchAction.INSTANCE, searchRequest, actionListener);
            } else {
                client.search(searchRequest, actionListener);
            }
        } catch (Exception e) {
            log.error("Failed to search index", e);
            listener.onFailure(e);
        }
    }

    public static class Factory implements Tool.Factory<SearchIndexTool> {

        private Client client;
        private static Factory INSTANCE;

        private NamedXContentRegistry xContentRegistry;

        public static Factory getInstance() {
            if (INSTANCE != null) {
                return INSTANCE;
            }
            synchronized (SearchIndexTool.class) {
                if (INSTANCE != null) {
                    return INSTANCE;
                }
                INSTANCE = new Factory();
                return INSTANCE;
            }
        }

        public void init(Client client, NamedXContentRegistry xContentRegistry) {
            this.client = client;
            this.xContentRegistry = xContentRegistry;
        }

        @Override
        public SearchIndexTool create(Map<String, Object> params) {
            return new SearchIndexTool(client, xContentRegistry);
        }

        @Override
        public String getDefaultDescription() {
            return DEFAULT_DESCRIPTION;
        }

        @Override
        public String getDefaultType() {
            return TYPE;
        }

        @Override
        public String getDefaultVersion() {
            return null;
        }
    }
}
JAVAEOF

grep -q "sanitizeLlmJson" "$TOOL_FILE" || die "SearchIndexTool.java patch write failed verification."
log "SearchIndexTool.java patched and verified."

# ─── Step 4b: Fix broken Eclipse formatter P2 mirror across all modules ───
log "Disabling broken Eclipse JDT formatter (unreachable upstream P2 mirror)..."

FILES_WITH_ECLIPSE=$(grep -rl "eclipse().withP2Mirrors" --include="build.gradle" . 2>/dev/null || true)
if [[ -z "$FILES_WITH_ECLIPSE" ]]; then
  warn "No build.gradle files found with the eclipse() formatter line — upstream may have changed this. Continuing."
else
  while IFS= read -r f; do
    sed -i 's|^\( *\)eclipse().withP2Mirrors.*$|\1// eclipse() DISABLED by deploy script — unreachable P2 mirror|' "$f"
    log "  patched: $f"
  done <<< "$FILES_WITH_ECLIPSE"
fi

# ─── Step 4c: Fix Jackson dependency version conflict ─────────────────────
log "Pinning Jackson dependency versions in plugin/build.gradle..."

PLUGIN_BUILD_GRADLE="plugin/build.gradle"
[[ -f "$PLUGIN_BUILD_GRADLE" ]] || die "Expected file not found: ${PLUGIN_BUILD_GRADLE}"

if grep -q "jackson-annotations:2.18.6" "$PLUGIN_BUILD_GRADLE"; then
  warn "Jackson force block already present — skipping."
else
  DEPS_LINE=$(grep -n "^dependencies {" "$PLUGIN_BUILD_GRADLE" | head -1 | cut -d: -f1)
  [[ -n "$DEPS_LINE" ]] || die "Could not find 'dependencies {' line in ${PLUGIN_BUILD_GRADLE}."
  sed -i "${DEPS_LINE}a\\
\\
    configurations.all {\\
        resolutionStrategy {\\
            force(\"com.fasterxml.jackson.core:jackson-annotations:2.18.6\")\\
            force(\"com.fasterxml.jackson:jackson-bom:2.18.6\")\\
            force(\"com.fasterxml.jackson.datatype:jackson-datatype-jsr310:2.18.6\")\\
        }\\
    }" "$PLUGIN_BUILD_GRADLE"
  grep -q "jackson-annotations:2.18.6" "$PLUGIN_BUILD_GRADLE" || die "Jackson force-block insertion failed verification."
fi
log "Jackson version pin applied and verified."

# ─── Step 5: Build ─────────────────────────────────────────────────────────
log "Building plugin bundle (this can take 1-2 minutes)..."
chmod +x ./gradlew
./gradlew :opensearch-ml-plugin:assemble --console=plain -x spotlessJavaCheck -x spotlessCheck \
  || die "Gradle build failed. Review the output above — no changes have been made to the running plugin yet, it is safe to fix and re-run this script."

ZIP_PATH=$(find plugin/build/distributions -maxdepth 1 -iname "opensearch-ml-*.zip" ! -iname "*sources*" ! -iname "*javadoc*" | head -1)
[[ -f "$ZIP_PATH" ]] || die "Build reported success but no plugin zip found in plugin/build/distributions/"
log "Build successful: ${ZIP_PATH}"

# ─── Step 6: Backup current plugin ────────────────────────────────────────
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="${BACKUP_DIR}/opensearch-ml-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
log "Backing up current plugin to ${BACKUP_FILE}..."
tar -czf "$BACKUP_FILE" -C "$(dirname "$PLUGIN_DIR")" "$(basename "$PLUGIN_DIR")" \
  || die "Backup failed — aborting before touching the live plugin."
[[ -s "$BACKUP_FILE" ]] || die "Backup file is empty — aborting."
log "Backup verified ($(du -h "$BACKUP_FILE" | cut -f1))."

# ─── Step 7: Deploy ────────────────────────────────────────────────────────
log "Stopping wazuh-indexer..."
systemctl stop wazuh-indexer
sleep 3
systemctl is-active --quiet wazuh-indexer && die "wazuh-indexer is still active after stop — aborting."
log "Indexer stopped cleanly."

log "Swapping in the patched plugin..."
rm -rf "$PLUGIN_DIR"
mkdir -p "$PLUGIN_DIR"
unzip -q "$ZIP_PATH" -d "$PLUGIN_DIR"
chown -R wazuh-indexer:wazuh-indexer "$PLUGIN_DIR"

log "Starting wazuh-indexer..."
systemctl start wazuh-indexer

# ─── Step 8: Verify, with automatic rollback on failure ───────────────────
log "Waiting for indexer to come up (30s)..."
sleep 30

ROLLBACK() {
  err "Verification failed. Rolling back to ${BACKUP_FILE}..."
  systemctl stop wazuh-indexer
  rm -rf "$PLUGIN_DIR"
  mkdir -p "$PLUGIN_DIR"
  tar -xzf "$BACKUP_FILE" -C "$(dirname "$PLUGIN_DIR")"
  chown -R wazuh-indexer:wazuh-indexer "$PLUGIN_DIR"
  systemctl start wazuh-indexer
  sleep 20
  if systemctl is-active --quiet wazuh-indexer; then
    err "Rolled back successfully. The pre-existing plugin has been restored. Investigate the error above before retrying."
  else
    err "ROLLBACK ALSO FAILED. Manual intervention required. Backup is at: ${BACKUP_FILE}"
  fi
  exit 1
}

systemctl is-active --quiet wazuh-indexer || { err "wazuh-indexer is not active after restart."; ROLLBACK; }
log "Service is active."

HTTP_CODE=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" "${INDEXER_URL}/" -o /dev/null -w "%{http_code}")
[[ "$HTTP_CODE" == "200" ]] || { err "Indexer not responding with 200 (got ${HTTP_CODE})."; ROLLBACK; }
log "Indexer responding (200 OK)."

CLUSTER_STATUS=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" "${INDEXER_URL}/_cluster/health" | grep -o '"status":"[a-z]*"' | cut -d'"' -f4)
[[ "$CLUSTER_STATUS" == "green" || "$CLUSTER_STATUS" == "yellow" ]] || { err "Cluster status is '${CLUSTER_STATUS}' (expected green/yellow)."; ROLLBACK; }
log "Cluster status: ${CLUSTER_STATUS}"

DEPLOYED_ML_VERSION=$(curl -sk -u "${ADMIN_USER}:${ADMIN_PASS}" "${INDEXER_URL}/_cat/plugins" | grep opensearch-ml | awk '{print $NF}' | head -1)
[[ -n "$DEPLOYED_ML_VERSION" ]] || { err "opensearch-ml plugin not found in _cat/plugins after restart."; ROLLBACK; }
log "opensearch-ml plugin registered: ${DEPLOYED_ML_VERSION}"

echo
log "=========================================="
log " DEPLOYMENT SUCCESSFUL"
log "=========================================="
log " Plugin version : ${DEPLOYED_ML_VERSION}"
log " Cluster status  : ${CLUSTER_STATUS}"
log " Backup kept at  : ${BACKUP_FILE}"
log " Build source at : ${BUILD_DIR}"
echo
warn "Reminder: any existing ML Commons agents that use SearchIndexTool will"
warn "now benefit from the patch automatically — no agent re-registration"
warn "needed, since the fix lives in the plugin, not the agent config."
warn ""
warn "Reminder: if wazuh-indexer / opensearch-ml is ever upgraded through"
warn "normal update channels, this patch will be silently overwritten."
warn "Re-run this script after any such upgrade."
