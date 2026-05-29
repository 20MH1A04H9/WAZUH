  <!--
=============================================================================
  agent.conf — VISWA Group — Advanced SOC + EDR
  Wazuh Manager : aiwazuh.socexperts.space
  Group         : VISWA
  Target OS     : Windows 11 ALL Versions
  FIX APPLIED   : Removed all CDATA blocks — agent.conf XML parser does not
                  support CDATA. All < > & characters are XML-escaped.
                  All <query> tags are explicitly closed.
  NOISE DROPPED (at agent — never sent to manager):
    4624 LogonType 0,4,5  SYSTEM/Batch/Service logons
    4634  Logoff
    4658  Handle closed
    4703  Token right adjusted
    4985  Transaction state changed
    5156  FW allowed connection  ← causes infinite loop!
    5158  Bind permitted
    5447  WFP filter change
    4799  Local group enumerated
    7036  Service state changed (System log)
=============================================================================
-->
  <agent_config>
    <!-- ================================================================
       ANTI-FLOOD BUFFER — increased for Sysmon EDR volume
       ================================================================ -->
    <client_buffer>
      <disabled>no</disabled>
      <queue_size>10000</queue_size>
      <events_per_second>1000</events_per_second>
    </client_buffer>
    <!-- ================================================================
       SECURITY EVENT LOG — Advanced SOC Whitelist
       XPATH query uses XML-escaped operators (no CDATA)
       &  =  &
       &lt;   =  <
       &gt;   =  >
       ================================================================ -->
    <localfile>
      <location>Security</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <reconnect_time>5s</reconnect_time>
      <query>Event/System[(EventID=1102 or EventID=4608 or EventID=4609 or EventID=4610 or EventID=4611 or EventID=4616 or EventID=4618 or EventID=4621 or EventID=4624 or EventID=4625 or EventID=4626 or EventID=4627 or EventID=4648 or EventID=4649 or EventID=4657 or EventID=4660 or EventID=4661 or EventID=4662 or EventID=4663 or EventID=4664 or EventID=4670 or EventID=4671 or EventID=4672 or EventID=4673 or EventID=4674 or EventID=4675 or EventID=4688 or EventID=4689 or EventID=4690 or EventID=4691 or EventID=4692 or EventID=4693 or EventID=4694 or EventID=4695 or EventID=4696 or EventID=4697 or EventID=4698 or EventID=4699 or EventID=4700 or EventID=4701 or EventID=4702 or EventID=4706 or EventID=4707 or EventID=4713 or EventID=4714 or EventID=4715 or EventID=4716 or EventID=4717 or EventID=4718 or EventID=4719 or EventID=4720 or EventID=4722 or EventID=4723 or EventID=4724 or EventID=4725 or EventID=4726 or EventID=4727 or EventID=4728 or EventID=4729 or EventID=4730 or EventID=4731 or EventID=4732 or EventID=4733 or EventID=4734 or EventID=4735 or EventID=4737 or EventID=4738 or EventID=4739 or EventID=4740 or EventID=4741 or EventID=4742 or EventID=4743 or EventID=4748 or EventID=4753 or EventID=4756 or EventID=4758 or EventID=4764 or EventID=4765 or EventID=4766 or EventID=4767 or EventID=4768 or EventID=4769 or EventID=4770 or EventID=4771 or EventID=4772 or EventID=4774 or EventID=4775 or EventID=4776 or EventID=4777 or EventID=4778 or EventID=4779 or EventID=4780 or EventID=4781 or EventID=4782 or EventID=4793 or EventID=4794 or EventID=4797 or EventID=4798 or EventID=4800 or EventID=4801 or EventID=4802 or EventID=4803 or EventID=4816 or EventID=4865 or EventID=4866 or EventID=4867 or EventID=4904 or EventID=4905 or EventID=4906 or EventID=4907 or EventID=4908 or EventID=4909 or EventID=4910 or EventID=4911 or EventID=4912 or EventID=4946 or EventID=4947 or EventID=4948 or EventID=4950 or EventID=4954 or EventID=4956 or EventID=4957 or EventID=4958 or EventID=5024 or EventID=5025 or EventID=5027 or EventID=5028 or EventID=5029 or EventID=5030 or EventID=5031 or EventID=5033 or EventID=5034 or EventID=5035 or EventID=5037 or EventID=5038 or EventID=5039 or EventID=5059 or EventID=5060 or EventID=5061 or EventID=5062 or EventID=5136 or EventID=5137 or EventID=5138 or EventID=5139 or EventID=5140 or EventID=5141 or EventID=5142 or EventID=5143 or EventID=5144 or EventID=5145 or EventID=5148 or EventID=5149 or EventID=5150 or EventID=5151 or EventID=5152 or EventID=5153 or EventID=5154 or EventID=5155 or EventID=5157 or EventID=5159 or EventID=5376 or EventID=5377 or EventID=5378 or EventID=5379 or EventID=5380 or EventID=5381 or EventID=5382 or EventID=5440 or EventID=5441 or EventID=5442 or EventID=5443 or EventID=5444 or EventID=5446 or EventID=5448 or EventID=5449 or EventID=5450 or EventID=5451 or EventID=5452 or EventID=5453 or EventID=5471 or EventID=5472 or EventID=5473 or EventID=5474 or EventID=5477 or EventID=6144 or EventID=6145 or EventID=6272 or EventID=6273 or EventID=6274 or EventID=6275 or EventID=6276 or EventID=6277 or EventID=6278 or EventID=6279 or EventID=6280 or EventID=6281 or EventID=6416 or EventID=6419 or EventID=6420 or EventID=6421 or EventID=6422 or EventID=6423 or EventID=6424) and not (EventID=4624 and (EventData[Data[@Name='LogonType']='0'] or EventData[Data[@Name='LogonType']='4'] or EventData[Data[@Name='LogonType']='5'])) and EventID!=4634 and EventID!=4658 and EventID!=4703 and EventID!=4985 and EventID!=4799 and EventID!=5156 and EventID!=5158 and EventID!=5447]</query>
    </localfile>
    <!-- ================================================================
       SYSTEM EVENT LOG — Service installs, crashes, driver failures
       Drops: 7036 service state changes (extremely noisy)
       ================================================================ -->
    <localfile>
      <location>System</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[(EventID=104 or EventID=1001 or EventID=1014 or EventID=1074 or EventID=1076 or EventID=6005 or EventID=6006 or EventID=6008 or EventID=6009 or EventID=6013 or EventID=7000 or EventID=7001 or EventID=7009 or EventID=7011 or EventID=7023 or EventID=7024 or EventID=7026 or EventID=7031 or EventID=7034 or EventID=7035 or EventID=7040 or EventID=7045) and EventID!=7036]</query>
    </localfile>
    <!-- ================================================================
       APPLICATION EVENT LOG — Crash / Error / Critical only
       Level 1=Critical, Level 2=Error — exploit crash side-effects
       ================================================================ -->
    <localfile>
      <location>Application</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[(EventID=1000 or EventID=1001 or EventID=1002 or EventID=1026 or EventID=1034) and (Level=1 or Level=2)]</query>
    </localfile>
    <!-- ================================================================
       SYSMON — Full EDR Telemetry
       Requires: Sysmon v15+ with SwiftOnSecurity config
       Install : https://github.com/SwiftOnSecurity/sysmon-config
       EID 1   Process creation (cmdline + hashes + parent)
       EID 2   File creation time changed  (timestomping)
       EID 3   Network connection
       EID 5   Process terminated
       EID 6   Driver loaded               (kernel implant)
       EID 7   Image / DLL loaded
       EID 8   CreateRemoteThread          (injection)
       EID 9   RawAccessRead               (disk-level cred dump)
       EID 10  Process accessed            (LSASS dump)
       EID 11  File created
       EID 12  Registry object add/delete
       EID 13  Registry value set
       EID 14  Registry object renamed
       EID 15  File stream created         (ADS)
       EID 16  Sysmon config changed
       EID 17  Named pipe created
       EID 18  Named pipe connected        (lateral movement)
       EID 19  WMI filter registered
       EID 20  WMI consumer registered
       EID 21  WMI consumer bound          (persistence)
       EID 22  DNS query
       EID 23  File deleted                (anti-forensics)
       EID 24  Clipboard capture
       EID 25  Process tampering           (hollowing/herpaderping)
       EID 26  File delete logged
       EID 27  File block executable
       EID 28  File block shredding
       EID 29  File executable detected
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-Sysmon/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=1 or EventID=2 or EventID=3 or EventID=5 or EventID=6 or EventID=7 or EventID=8 or EventID=9 or EventID=10 or EventID=11 or EventID=12 or EventID=13 or EventID=14 or EventID=15 or EventID=16 or EventID=17 or EventID=18 or EventID=19 or EventID=20 or EventID=21 or EventID=22 or EventID=23 or EventID=24 or EventID=25 or EventID=26 or EventID=27 or EventID=28 or EventID=29]</query>
    </localfile>
    <!-- ================================================================
       POWERSHELL SCRIPT BLOCK LOGGING
       Catches encoded / obfuscated / fileless attacks
       Requires GPO: Script Block Logging = Enabled
       EID 4103  Module / pipeline execution
       EID 4104  Script block  ← catches IEX, Invoke-Mimikatz, etc.
       EID 4105  Script start
       EID 4106  Script stop
       EID 40961 Console starting
       EID 40962 Console ready
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-PowerShell/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=4103 or EventID=4104 or EventID=4105 or EventID=4106 or EventID=40961 or EventID=40962]</query>
    </localfile>
    <!-- PowerShell classic (legacy host) -->
    <localfile>
      <location>Windows PowerShell</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=400 or EventID=403 or EventID=500 or EventID=600 or EventID=800]</query>
    </localfile>
    <!-- ================================================================
       MICROSOFT DEFENDER ANTIVIRUS
       Detections, scan failures, RTP disable, exclusion changes
       EID 1006/1116/1117  Malware detected / action taken
       EID 5001            Real-time protection DISABLED  ← CRITICAL
       EID 5007            Config changed (attacker adds exclusion)
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-Windows Defender/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=1006 or EventID=1007 or EventID=1008 or EventID=1009 or EventID=1010 or EventID=1013 or EventID=1014 or EventID=1015 or EventID=1116 or EventID=1117 or EventID=1118 or EventID=1119 or EventID=2001 or EventID=2002 or EventID=2003 or EventID=2004 or EventID=2005 or EventID=2006 or EventID=2007 or EventID=2010 or EventID=2011 or EventID=3002 or EventID=3007 or EventID=5001 or EventID=5004 or EventID=5007 or EventID=5008 or EventID=5009 or EventID=5010 or EventID=5012]</query>
    </localfile>
    <!-- ================================================================
       WINDOWS FIREWALL — Advanced Security
       Rule changes, profile changes
       EID 2003  Setting changed
       EID 2004  Rule added
       EID 2005  Rule modified
       EID 2006  Rule deleted
       EID 2009  Could not load rules
       EID 2033  All rules deleted
       EID 2052  Rule parser error
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-Windows Firewall With Advanced Security/Firewall</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=2003 or EventID=2004 or EventID=2005 or EventID=2006 or EventID=2009 or EventID=2033 or EventID=2052]</query>
    </localfile>
    <!-- ================================================================
       TASK SCHEDULER — Persistence T1053.005
       EID 106  Task registered
       EID 140  Task updated
       EID 141  Task deleted
       EID 200  Action started
       EID 201  Action completed
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-TaskScheduler/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=106 or EventID=140 or EventID=141 or EventID=200 or EventID=201]</query>
    </localfile>
    <!-- ================================================================
       WMI ACTIVITY — Fileless Persistence T1546.003
       EID 5860  Permanent subscription registered  ← CRITICAL
       EID 5861  Active script consumer bound       ← CRITICAL
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-WMI-Activity/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=5857 or EventID=5858 or EventID=5859 or EventID=5860 or EventID=5861]</query>
    </localfile>
    <!-- ================================================================
       WINRM — Lateral Movement T1021.006
       EID 6    WSMan session created
       EID 8    WSMan session closed
       EID 15   Inbound activity
       EID 16   Connection failure
       EID 33   WSMan shell created
       EID 91   Session created
       EID 168  Auth attempt
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-WinRM/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=6 or EventID=8 or EventID=15 or EventID=16 or EventID=33 or EventID=91 or EventID=168]</query>
    </localfile>
    <!-- ================================================================
       RDP / TERMINAL SERVICES — Lateral Movement T1021.001
       LocalSessionManager events
       EID 21   Session logon succeeded
       EID 22   Shell start received
       EID 23   Session logoff
       EID 24   Session disconnected
       EID 25   Session reconnected
       EID 39   Disconnected by another session
       EID 40   Connected from another session
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-TerminalServices-LocalSessionManager/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=21 or EventID=22 or EventID=23 or EventID=24 or EventID=25 or EventID=39 or EventID=40]</query>
    </localfile>
    <!-- RDP RemoteConnectionManager -->
    <localfile>
      <location>Microsoft-Windows-TerminalServices-RemoteConnectionManager/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=261 or EventID=1149 or EventID=1158]</query>
    </localfile>
    <!-- ================================================================
       BITS CLIENT — C2 / Data Exfil T1197
       Stealthy download/upload via Background Intelligent Transfer
       EID 3   Job created
       EID 59  Transfer started
       EID 60  Transfer completed
       EID 61  Transfer cancelled
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-Bits-Client/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=3 or EventID=59 or EventID=60 or EventID=61]</query>
    </localfile>
    <!-- ================================================================
       APPLOCKER — Defense Evasion Detection T1562.001
       Blocked execution attempts are high-signal indicators
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-AppLocker/EXE and DLL</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
    </localfile>
    <localfile>
      <location>Microsoft-Windows-AppLocker/MSI and Script</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
    </localfile>
    <localfile>
      <location>Microsoft-Windows-AppLocker/Packaged app-Deployment</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
    </localfile>
    <!-- ================================================================
       CODE INTEGRITY / WDAC — Windows 11 Native
       Driver blocks, unsigned code, policy enforcement
       EID 3033  Application control blocked (enforce mode)
       EID 3034  Application control blocked (audit mode)
       EID 3076  Audit mode — would have blocked
       EID 3077  Enforce mode — blocked
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-CodeIntegrity/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=3001 or EventID=3002 or EventID=3003 or EventID=3004 or EventID=3010 or EventID=3023 or EventID=3033 or EventID=3034 or EventID=3076 or EventID=3077 or EventID=3089 or EventID=3099]</query>
    </localfile>
    <!-- ================================================================
       GROUP POLICY — Domain Policy Modification T1484
       EID 1085  Policy application failed
       EID 1125  GPO failed to apply
       EID 1127  Stage 2 processing failed
       EID 1129  Processing of GPO failed
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-GroupPolicy/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=1085 or EventID=1125 or EventID=1127 or EventID=1129]</query>
    </localfile>
    <!-- ================================================================
       DNS CLIENT — DNS Tunneling / C2 T1071.004
       Track DNS resolutions for C2 beacon detection
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-DNS-Client/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=3006 or EventID=3008 or EventID=3020]</query>
    </localfile>
    <!-- ================================================================
       DRIVER FRAMEWORK — Hardware Implant / BadUSB Detection
       EID 2003  Device connected
       EID 2004  Device disconnected
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-DriverFrameworks-UserMode/Operational</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
      <query>Event/System[EventID=2003 or EventID=2004 or EventID=2100 or EventID=2101]</query>
    </localfile>
    <!-- ================================================================
       SMARTSCREEN — Windows 11 Download Block T1204
       ================================================================ -->
    <localfile>
      <location>Microsoft-Windows-SmartScreen/Debug</location>
      <log_format>eventchannel</log_format>
      <only-future-events>yes</only-future-events>
    </localfile>
  </agent_config>
