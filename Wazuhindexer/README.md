## Wazuh indexer tuning & JVM Memory

When the system is swapping memory, the Wazuh indexer may not work as expected. Therefore, it is important for the health of the Wazuh indexer node that none of the Java Virtual Machine (JVM) is ever swapped out to disk. To prevent any Wazuh indexer memory from being swapped out, configure the Wazuh indexer to lock the process address space into RAM as follows.
 
```
curl -fsSL https://raw.githubusercontent.com/20MH1A04H9/WAZUH/refs/heads/main/Wazuhindexer/wazuh-auto-config.sh -o ~/wazuh-auto-config.sh && bash ~/wazuh-auto-config.sh
```
