#! /usr/bin/perl
#
# Mailstats parser extend for NET-SNMP
# Supports: Exim/Postfix/Sendmail/Scanners/DKIM/SPF
# Dovecot/courier/cyrus/zarafa-gateway
#
# Based on a script by Matthew Newton
##
# Modified by: David "Dinde" OH <david@ows.fr> - http://www.owns.fr
# Date: 14/11/2013: Release 1
# Version: 1.1
## 
use strict;

## Options to set up here.
# $mta is the used mta to get statistics from. (postfix/sendmail/exim/)
# $maillog is the latest Exim main log.
# $mainlogold is the last rotated out main log.
# $conf is where to store the current state file.
# $statsfile is the file that contains the current data.
# $archive is a directory. If it exists then old data is written there too.
# $popimaplog is the file that contains POP/IMAP logs.
# $popimaplogold is the last rotated file that contains POP/IMAP logs.

# Select your MTA and the log files to be parsed
# Exim example
#my $mta = "exim";
#my $mainlog = "/var/log/exim4/mainlog";
#my $mainlogold = "/var/log/exim4/mainlog.1";
#my $popimaplog = "/var/log/mail.log";
#my $popimaplogold "/var/log/mail.log.1";
# Postfix example
my $mta = "postfix";
my $mainlog = "/var/log/mail.log";
my $mainlogold = "/var/log/mail.log.1";
# Sendmail example
# TODO

# States/Logs files
my $conf = "/var/run/mxstats-current-state";
my $confpopimap = "/var/run/popimap-current-state";
my $statsfile = "/var/tmp/mxstats";
my $archive = "/var/log/mxstats";

# read conf file of when last run and where we got to
my %stats = ();

# set some defaults. If the current-state file does not exist, lets
# start searching through the current mainlog from the beginning.
my $seek = 0;
my $inode = inode_number($mainlog);
my $cantseek = 0;

if (-r $conf) {
  open CONF, "< $conf";
  while (<CONF>) {
    chomp;
    s/^\s*//;
    s/\s*$//;
    next if /^$/;
    if (/^inode=(\d+)$/) {
      $inode = $1;
    }
    if (/^seek=(.*)$/) {
      $seek = $1;
    }
  }
  close CONF;
}

# Exim is on separate log from imap pop, so let's basicly do the same than above.
if ($mta =~ /^exim/) {
	my $seekbis = 0;
	my $inodebis = inodebis_number($popimaplog);
	my $cantseekbis = 0;

	if (-r $confpopimap) {
	  open CONFPOPIMAP, "< $confpopimap";
	  while (<CONFPOPIMAP>) {
	    chomp;
	    s/^\s*//;
	    s/\s*$//;
	    next if /^$/;
	    if (/^inodebis=(\d+)$/) {
	      $inodebis = $1;
	    }
	    if (/^seekbis=(.*)$/) {
	      $seekbis = $1;
	    }
	  }
	close CONFPOPIMAP;
	}
}

# .1.3.6.1.4.1.2021.13.69
$stats{"in"} = 0;                 #.01 in
$stats{"out"} = 0;                #.02 out
$stats{"queued"} = 0;             #.03 Mail in (black) queue
$stats{"bounces"} = 0;            #.04 Bounced mails
$stats{"localsmtp"} = 0;	  #.05 Local SMTP delivery - Accepted mails
$stats{"remotesmtp"} = 0;         #.06 Remote SMTP delivery - Accepted Relay users
$stats{"remotesmtpdefer"} = 0;    #.07 Remote SMTP delivery - Defered mails
$stats{"relaynotpermitted"} = 0;  #.08 relay not permitted
$stats{"rejectrcptunknown"} = 0;  #.09 rejected RCPT - User unknown; rejecting
$stats{"unexpectdisconnect"} = 0; #.10 unexpected disconnection
$stats{"blacklisted"} = 0;        #.11 Remote SMTP delivery - Failed blacklist
$stats{"senderverifyfail"} = 0;   #.12 Sender verify failed
$stats{"rcptreject"} = 0;         #.13 reject RCPT other reasons
$stats{"authfail"} = 0;           #.14 Authentication failed for account
$stats{"authpass"} = 0;           #.15 Failed SMTP auth sessions
$stats{"spam"} = 0;               #.16 reported spam by Scanner
$stats{"virus"} = 0;              #.17 reported virus by Scanner
$stats{"dkimsuccess"} = 0;        #.18 DKIM succeeded
$stats{"dkimfail"} = 0;           #.19 DKIM failed/invalid
$stats{"dkimsigned"} = 0;         #.20 DKIM signed sent mail
$stats{"rejrbl"} = 0;             #.21 Found in RBL
$stats{"greylistdefer"} = 0;      #.22 Greylist defer
$stats{"spfpass"} = 0;            #.23 SPF pass
$stats{"spfneutral"} = 0;         #.24 SPF neutral
$stats{"spffailed"} = 0;	  #.25 SPF failed
	#.26 IMAP(S) Login Failed
	#.27 IMAP(S) Login Success
	#.28 IMAP(S) Active Connex (netstat ?)
	#.29 IMAP(S) Max Threads (config)
	#.30 IMAP(S) Active Threads (ps ?)
	#.31 POP(S) Login Failed
	#.32 POP(S) Login Success
	#.33 POP(S) Active Connex
	#.34 POP(S) Max Threads (config)
	#.35 POP(S) Active Threads (ps ?)

# see if we can seek to current position in the mainlog. If not, then
# it has most likely been rotated
open LOG, "< $mainlog" or die "cannot open log file: $mainlog!";
if (!seek(LOG, $seek, 0)) {
  $cantseek = 1;
}
close LOG;

if ($inode != inode_number($mainlog) or
  $cantseek or
  $inode == inode_number($mainlogold)) {
  # we have changed to a new log file; read the previous mainlog first
  read_log($mainlogold, $seek, \%stats);
  $inode = inode_number($mainlog);
  $seek = 0;
}

$seek = read_log($mainlog, $seek, \%stats);

if (!read_queue(\%stats)) {
  $stats{"queued"} = -1;
  $stats{"bounces"} = -1;
}

write_stats($statsfile, \%stats);

# create config file
open CONF, "> $conf";
print CONF "inode=$inode\n";
print CONF "seek=$seek\n";
close CONF;

if (defined $archive and $archive ne "" and -d $archive) {
	  write_stats($archive."/".now_time(), \%stats);
}

# TODO: if mta exim we do the same than above for the second log file

exit;

sub now_time
{
  my @n = gmtime();
  my ($y, $m, $d) = ($n[5]+1900, $n[4]+1, $n[3]);
  my ($hr, $mn, $sc) = ($n[2], $n[1], $n[0]);
  $m = "0$m" if ($m < 10);
  $d = "0$d" if ($d < 10);
  $hr = "0$hr" if ($hr < 10);
  $mn = "0$mn" if ($mn < 10);
  $sc = "0$sc" if ($sc < 10);
  return "$y-$m-$d-$hr-$mn-$sc";
}

sub inode_number
{
  my $file = shift;
  my ($dummy, $inode) = stat($file);
  return $inode;
}

sub read_log
{
  my ($file, $seek, $stats) = @_;
  my $prevline = undef;
  my $line;
  my ($prevpos, $pos);
  local *LOG;

  open LOG, "< $file" or die "cannot open exim log file $file!";

  if (!seek(LOG, $seek, 0)) {
    close LOG;
    return $seek;
  }
  while ($line = <LOG>) {
	  if (defined $prevline) {
		  if ($mta =~ /^exim/) {
			  if ($line =~ /<=/) { $$stats{"in"}++; }
			  if ($line =~ /[=-]>/) { $$stats{"out"}++; }
			  if ($line =~ /Recipient address rejected: Greylisted/) {$$stats{"greylistdefer"}++;
			  } elsif ($line =~ /relay not permitted/) {$$stats{"relaynotpermitted"}++;
			  } elsif ($line =~ /User unknown\; rejecting/) {$$stats{"rejectrcptunknown"}++;
			  } elsif ($line =~ /rejected by local_scan/) {$$stats{"spam"}++;
			  } elsif ($line =~ /Blocked by SpamAssassin/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(Passed|Blocked) SPAM(?:MY)?\b/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(Passed|Not-Delivered)\b.*\bquarantine spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /\bcontains spam\b/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^(?:spamd: )?identified spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /spam detected from/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^\s*SPAM/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^identified spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(?:RBL|Razor|Spam)/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^Spam Checks: Found ([0-9]+) spam messages/) {$$stats{"spam"}++;
			  } elsif ($line =~ /Spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /\bspam_status\=(?:yes|spam)/) {$$stats{"spam"}++;
			  } elsif ($line =~ /\[DATA\] Virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /Blocked INFECTED/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(Passed |Blocked )?INFECTED\b/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(Passed |Blocked )?BANNED\b/) {$$stats{"blacklisted"}++;
			  } elsif ($line =~ /^Virus found\b/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^VIRUS/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^\*+ Virus\b/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(?:result: )?CLAMAV/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(Virus Scanning: Found)/) {$$stats{"virus"}++;
			  } elsif ($line =~ /status=VIRUS/) {$$stats{"virus"}++;
			  } elsif ($line =~ /Intercepted/) {$$stats{"virus"}++;
			  } elsif ($line =~ /clamd: found/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^Alert!/) {$$stats{"virus"}++;
			  } elsif ($line =~ /blocked\.$/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^[0-9A-F]+: virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^infected/) {$$stats{"virus"}++;
			  } elsif ($line =~ /Virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /local_delivery/) {$$stats{"localsmtp"}++;
			  } elsif ($line =~ /remote_smtp defer/) {$$stats{"remotesmtpdefer"}++;
			  } elsif ($line =~ /550 5\./) {$$stats{"remotesmtpdefer"}++;
			  } elsif ($line =~ /\[invalid/) {$$stats{"dkimfail"}++;
			  } elsif ($line =~ /\[verification succeeded\]/) {$$stats{"dkimsuccess"}++;
			  } elsif ($line =~ /\[verification failed/) {$$stats{"dkimfail"}++;
			  } elsif ($line =~ /TODO DKIM SENT SIGNED/) {$$stats{"dkimsigned"}++;
			  } elsif ($line =~ /TODO SPF PASS/) {$$stats{"spfpass"}++;
			  } elsif ($line =~ /TODO SPF NEUTRAL/) {$$stats{"spfneutral"}++;
			  } elsif ($line =~ /TODO SPF FAILED/) {$$stats{"spffailed"}++;
			  } elsif ($line =~ /535 Incorrect authentication data/) {$$stats{"authfail"}++;
			  } elsif ($line =~ /A=fixed_login/) {$$stats{"authpass"}++;
			  } elsif ($line =~ /unexpected disconnection/) {$$stats{"unexpectdisconnect"}++;
			  } elsif ($line =~ /554 5\./) {$$stats{"blacklisted"}++;
			  } elsif ($line =~ /Sender verify failed/) {$$stats{"senderverifyfail"}++;
			  } elsif ($line =~ /remote_smtp/) {$$stats{"remotesmtp"}++;
			  } elsif ($line =~ /rejected because .* is in a black list at/) {$$stats{"rejrbl"}++;
			  } elsif ($line =~ /rejected RCPT.*: found in/) {$$stats{"rejrbl"}++;
			  } elsif ($line =~ /rejected RCPT/) {$$stats{"rcptreject"}++;
			  }
		  } elsif ($mta =~ /^postfix/) {
			  if ($line =~ /status=sent/) {$$stats{"out"}++; }
			  if ($line =~ /client=/) {$$stats{"in"}++; }
			  if ($line =~ /status=bounced/) {$$stats{"bounces"}++; }
			  if ($line =~ /NOQUEUE: reject: RCPT .*: 450.* Recipient address rejected: Greylisted/) {$$stats{"greylistdefer"}++;
			  } elsif ($line =~ /NOQUEUE: reject: .* Relay access denied\;/) {$$stats{"relaynotpermitted"}++;
			  } elsif ($line =~ /NOQUEUE: reject: .* Recipient address rejected: User unknown/) {$$stats{"rejectrcptunknown"}++;
			  } elsif ($line =~ /Blocked SPAM/) {$$stats{"spam"}++;
			  } elsif ($line =~ /Passed SPAMMY/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^(?:spamd: )?identified spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /spam detected from/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^\s*SPAM/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^identified spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(?:RBL|Razor|Spam)/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^Spam Checks: Found ([0-9]+) spam messages/) {$$stats{"spam"}++;
			  } elsif ($line =~ /Spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /\bspam_status\=(?:yes|spam)/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(Passed|Blocked) SPAM(?:MY)?\b/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(Passed|Not-Delivered)\b.*\bquarantine spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /\bcontains spam\b/) {$$stats{"spam"}++;
			  } elsif ($line =~ /Blocked by SpamAssassin/) {$$stats{"spam"}++;
			  } elsif ($line =~ /NOQUEUE: reject: .*: 554.* blocked using virbl.dnsbl.bit.nl/) {$$stats{"virus"}++;
			  } elsif ($line =~ /Blocked INFECTED/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(Virus Scanning: Found)/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(Passed |Blocked )?INFECTED\b/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(Passed |Blocked )?BANNED\b/) {$$stats{"blacklisted"}++;
			  } elsif ($line =~ /^Virus found\b/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^VIRUS/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^\*+ Virus\b/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^Alert!/) {$$stats{"virus"}++;
			  } elsif ($line =~ /blocked\.$/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^infected/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(?:result: )?CLAMAV/) {$$stats{"virus"}++;
			  } elsif ($line =~ /Intercepted/) {$$stats{"virus"}++;
			  } elsif ($line =~ /clamd: found/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^Alert!/) {$$stats{"virus"}++;
			  } elsif ($line =~ /blocked\.$/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^[0-9A-F]+: virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /infected/) {$$stats{"virus"}++;
			  } elsif ($line =~ /status=VIRUS/) {$$stats{"virus"}++;
			  } elsif ($line =~ /Virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /relay=127\.0\.0\.1.* status=sent/) {$$stats{"localsmtp"}++;
			  } elsif ($line =~ /relay=(?!127\.0\.0\.1).* status=deferred/) {$$stats{"remotesmtpdefer"}++;
			  } elsif ($line =~ /TODO DKIM INVALID/) {$$stats{"dkimfail"}++;
			  } elsif ($line =~ /DKIM verification successful/) {$$stats{"dkimsuccess"}++;
			  } elsif ($line =~ /dkim-filter .* no signature data/) {$$stats{"dkimfail"}++;
			  } elsif ($line =~ /DKIM-Signature header added/) {$$stats{"dkimsigned"}++;
			  } elsif ($line =~ /Received-SPF: pass/) {$$stats{"spfpass"}++;
			  } elsif ($line =~ /Received-SPF: none/) {$$stats{"spfneutral"}++;
			  } elsif ($line =~ /Received-SPF: neutral/) {$$stats{"spfneutral"}++;
			  } elsif ($line =~ /Received-SPF: softfail/) {$$stats{"spffailed"}++;
			  } elsif ($line =~ /Received-SPF: permerror/) {$$stats{"spffailed"}++;
			  } elsif ($line =~ /NOQUEUE: milter-reject: .* 550.* rejected by spfmilter;/) {$$stats{"spffailed"}++;
			  } elsif ($line =~ /authentication fail/) {$$stats{"authfail"}++;
			  } elsif ($line =~ /sasl_method=.* sasl_username=/) {$$stats{"authpass"}++;
			  } elsif ($line =~ /lost connection after (?!CONNECT)/) {$$stats{"unexpectdisconnect"}++;
			  } elsif ($line =~ /NOQUEUE: reject: .* Sender address rejected/) {$$stats{"senderverifyfail"}++;
			  } elsif ($line =~ /relay=(?!127\.0\.0\.1).* status=sent/) {$$stats{"remotesmtp"}++;
			  } elsif ($line =~ /clamav-milter: .* infected by/) {$$stats{"virus"}++;
			  } elsif ($line =~ /NOQUEUE: milter-reject:/) {$$stats{"rcptreject"}++;
			  } elsif ($line =~ /NOQUEUE: reject: .* 554.* blocked using/) {$$stats{"rejrbl"}++;
			  } elsif ($line =~ /NOQUEUE: reject: .* Recipient address rejected:/) {$$stats{"rcptreject"}++;
			  } elsif ($line =~ /NOQUEUE: reject: .* 554 5\.7\.1/) {$$stats{"blacklisted"}++;
			  }
			  # TODO: Add the regexp for courier imap/pop dovecot zarafa-gateway (zimbra ?)
		  } elsif ($mta =~ /^sendmail/) {
			  if ($line =~ /Greylisting in action/) {$$stats{"greylistdefer"}++;
			  } elsif ($line =~ /^([^:\s]+): to=.*, delay=.* stat=queued/) {$$stats{"queued"}++;
			  } elsif ($line =~ /^([^:\s]+): to=.*, delay=.*, mailer=local,.*, stat=.*/) {$$stats{"localsmtp"}++;
			  } elsif ($line =~ /mailer=relay .* stat=Sent/) {$$stats{"remotesmtp"}++;
			  } elsif ($line =~ /ruleset=check_XS4ALL/) {$$stats{"rejrbl"}++;
			  } elsif ($line =~ /lost input channel/) {$$stats{"unexpectdisconnect"}++;
			  } elsif ($line =~ /Relaying denied/) {$$stats{"relaynotpermitted"}++;
			  } elsif ($line =~ /ruleset=check_rcpt/) {$$stats{"rcptreject"}++;
			  } elsif ($line =~ /553 5\.3\.0 .* Spam blocked/) {$$stats{"rejrbl"}++;
			  } elsif ($line =~ /stat=Deferred/) {$$stats{"remotesmtpdefer"}++;
			  } elsif ($line =~ /stat=virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /ruleset=check_relay/) {$$stats{"rejrbl"}++;
			  } elsif ($line =~ /virbl/) {$$stats{"rejrbl"}++;
			  } elsif ($line =~ /sender blocked/) {$$stats{"blacklisted"}++;
			  } elsif ($line =~ /sender denied/) {$$stats{"rcptreject"}++;
			  } elsif ($line =~ /recipient denied/) {$$stats{"rcptreject"}++;
			  } elsif ($line =~ /recipient unknown/) {$$stats{"rejectrcptunknown"}++;
			  } elsif ($line =~ /User unknown$/) {$$stats{"bounces"}++;
			  } elsif ($line =~ /Milter: .* reject=55/) {$$stats{"rcptreject"}++;
			  } elsif ($line =~ /Blocked by SpamAssassin/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(Passed|Blocked) SPAM(?:MY)?\b/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(Passed|Not-Delivered)\b.*\bquarantine spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(Passed |Blocked )?INFECTED\b/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(Passed |Blocked )?BANNED\b/) {$$stats{"blacklisted"}++;
			  } elsif ($line =~ /milter=clamav-milter, quarantine=quarantined by clamav-milter/) {$$stats{"virus"}++;
			  } elsif ($line =~ /AUTH=.*, relay=.*, authid=.*, mech=.*, bits=/) {$$stats{"authpass"}++;
			  } elsif ($line =~ /235 2.0.0 OK Authenticated/) {$$stats{"authpass"}++;
			  } elsif ($line =~ /Password verification failed/) {$$stats{"authfail"}++;
			  } elsif ($line =~ /reject=403 4.7.0 authentication failed/) {$$stats{"authfail"}++;
			  } elsif ($line =~ /AUTH failure/) {$$stats{"authfail"}++;
			  } elsif ($line =~ /TODO DKIM SUCCESS/) {$$stats{"dkimsuccess"}++;
			  } elsif ($line =~ /TODO DKIM FAILED/) {$$stats{"dkimfail"}++;
			  } elsif ($line =~ /TODO DKIM SENT SIGNED/) {$$stats{"dkimsigned"}++;
			  } elsif ($line =~ /TODO SPF PASS/) {$$stats{"spfpass"}++;
			  } elsif ($line =~ /TODO SPF NEUTRAL/) {$$stats{"spfneutral"}++;
			  } elsif ($line =~ /TODO SPF FAILED/) {$$stats{"spffailed"}++;
			  } elsif ($line =~ /^Virus found/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^VIRUS/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^\*+ Virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^Alert!/) {$$stats{"virus"}++;
			  } elsif ($line =~ /blocked/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^infected/) {$$stats{"virus"}++;
			  } elsif ($line =~ /(?:result: )?CLAMAV/) {$$stats{"virus"}++;
			  } elsif ($line =~ /Intercepted/) {$$stats{"virus"}++;
			  } elsif ($line =~ /clamd: found/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^Alert!/) {$$stats{"virus"}++;
			  } elsif ($line =~ /blocked\.$/) {$$stats{"virus"}++;
			  } elsif ($line =~ /^[0-9A-F]+: virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /infected/) {$$stats{"virus"}++;
			  } elsif ($line =~ /Virus/) {$$stats{"virus"}++;
			  } elsif ($line =~ /contains spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^(?:spamd: )?identified spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /spam detected from/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^SPAM/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^identified spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /(?:RBL|Razor|Spam)/) {$$stats{"spam"}++;
			  } elsif ($line =~ /^Spam Checks: Found ([0-9]+) spam messages/) {$$stats{"spam"}++;
			  } elsif ($line =~ /Spam/) {$$stats{"spam"}++;
			  } elsif ($line =~ /spam_status\=(?:yes|spam)/) {$$stats{"spam"}++;
			  } elsif ($line =~ /mailer=esmtp/) {$$stats{"out"}++;
			  } elsif ($line =~ /mailer=/) {$$stats{"in"}++;
			  } elsif ($line =~ /stat=Sent/) {$$stats{"out"}++;
			  }
			  # TODO: Add the regexp for courier imap/pop dovecot zarafa-gateway (zimbra ?)
		  }
	  }	
	  $prevline = $line;
	  $prevpos = $pos;
	  $pos = tell LOG;
  }
  close LOG;

  $prevpos = $seek unless defined $prevpos;

  return $prevpos;
}

# TODO: if mta exim Create the same parser than above for the second log file (imap/pop)

# TODO: Get with ps & netstats threads/conex status
sub read_queue
{
	if ($mta =~ /^exim/) {
		my $stats = shift;
		my $queued = 0;
		my $bounces = 0;
		open Q, "/usr/sbin/exim -bp |" or return 0;
		while (<Q>) {
			$$stats{"queued"}++ if (/\</);
			$$stats{"bounces"}++ if (/\<\>/);
		}
		close Q;
		return 1;
	} elsif ($mta =~ /^postfix/) {
		my $queued = 0;
		open MAILQ, "/usr/bin/mailq|" or return 0;
		my @tmpstats="";
		while (<MAILQ>) {
			@tmpstats = split(/ /, $_);
			if ($_ =~ m/^Mail queue is empty$/) {
				$tmpstats[4] = 0;
			}
		}
		chomp(@tmpstats);
		$stats{"$queued"} = $tmpstats[4];
	}
	close Q;
	return 1;
}

sub write_stats
{
  my ($file, $stats) = @_;
  local *STATS;

  open STATS, "> $file";
  print STATS <<EOF;
$$stats{"in"}
$$stats{"out"}
$$stats{"queued"}
$$stats{"bounces"}
$$stats{"localsmtp"}
$$stats{"remotesmtp"}
$$stats{"remotesmtpdefer"}
$$stats{"relaynotpermitted"}
$$stats{"rejectrcptunknown"}
$$stats{"unexpectdisconnect"}
$$stats{"blacklisted"}
$$stats{"senderverifyfail"}
$$stats{"rcptreject"}
$$stats{"authfail"}
$$stats{"authpass"}
$$stats{"spam"}
$$stats{"virus"}
$$stats{"dkimsuccess"}
$$stats{"dkimfail"}
$$stats{"dkimsigned"}
$$stats{"rejrbl"}
$$stats{"greylistdefer"}
$$stats{"spfpass"}
$$stats{"spfneutral"}
$$stats{"spffailed"}
EOF
  close STATS;
}
