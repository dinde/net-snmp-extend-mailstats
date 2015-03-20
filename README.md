snmp-extend-mxstats
===================
* Version: 1.x-beta3-rc1 - David "Dinde" <kayser@euroserv.com> 17/11/2013

Script to provide a snmp extend with statistics for Exim/Postfix/Sendmail and many scanners (Virus/Spam) supporting DKIM/SPF/Greylist.

Used OID: UCD-SNMP-MIB::ucdExperimental.69 mx-stats (.1.3.6.1.4.1.2021.13.69). It's not used anywhere and who do not like 69 ? :)

## Suppported:
### MTA: 
- Exim4: Tested against exim4/sa-exim/spamassassin/dkim/greylist
- Postfix: Tested against postfix/amavisd/spamassassin/postgrey
- Sendmail: Not tested (yet).

### Scanners: 
- amavisd
- Vexira
- Antivir Mailgate
- avcheck
- Spamassassin
- clamd
- dspam
- spampd
- drweb-postfix
- drweb
- sa-exim
- BlackHole
- MailScanner
- clamsmtpd
- clamav-milter
- smtp-vilter
- Antivir milter
- bogofilter

## Installation
- 1/ Download it !
* wget -O /usr/sbin/mxstats.pl https://raw.github.com/dinde/snmp-extend-mxstats/master/mxstats.pl

- 2/ Edit the configuration block specifying where the logs files are located.
* {vim,nano} /usr/sbin/mxstats.pl

- 3/ Run it to ensure it is working correctly before placing the cron
* wget -O /etc/cron.d/mxstats https://raw.github.com/dinde/snmp-extend-mxstats/master/cron/mxstats

- 4/ Adapt your cron execution time according your rrdstep. Usualy 300seconds step so cron will be 5mn.

- 5/ Extend your snmp by adding the following line to the end of: /etc/snmp/snmpd.conf
extend .1.3.6.1.4.1.2021.13.69 mx-stats /bin/cat /var/tmp/mxstats

- 6/ Test it ! It should return 25 values !
snmpwalk -v2c -c public YOUR.SERVER.TLD .1.3.6.1.4.1.2021.13.69

## Installation of Opennms files
There is 2 flavours of datacollection file.
* mailstats-gauge.xml which uses a gauge and need the cron to be sync with your  data collection time (example: rrdstep 300 = 5mn = cron 5mn)
* mailstats-counter.xml which uses a counter64 instead and does not need any sync on cron.
- 1/ Download datacollection file to your opennms folder:
wget -O $OPENNMS_HOME/datacollection/mailstats.xml https://raw.github.com/dinde/snmp-extend-mxstats/master/opennms/datacollection/mailstats-gauge.xml
or
wget -O $OPENNMS_HOME/datacollection/mailstats.xml https://raw.github.com/dinde/snmp-extend-mxstats/master/opennms/datacollection/mailstats-counter.xml
- 2/ Edit your datacollection-config.xml and Add:
        <include-collection dataCollectionGroup="Mailstats"/>

- 3/ Download graphs definitions to your opennms folder:
wget -O $OPENNMS_HOME/snmp-graph.properties.d/mailstats-graph.properties https://raw.github.com/dinde/snmp-extend-mxstats/master/opennms/snmp-graph.properties.d/mailstats-graph.properties

- 4/ Restart Opennms, rescan the node where the script run and enjoy the new graphs on "Node-level Performance Data"

## TODO before release of version 1
- Find more log samples and integrate the missing regexp.
- Implementation of IMAP(S)/POP3(S) statistics collections for Dovecot 1.x/2.x, Courier, Cyrus, Zarafa Gateway.
- More tests ...
- A new screenshot up to date for the wiki page

## Contribution
This script makes sense if people using it add more and more regexp to fit their needs.
This will make it naturaly better. Don't hesitate to request pull on github.
