#!/usr/bin/perl -w
#########################################################################
# Script:       check_ibm_ts_tape.pl					#
# Author:       Claudio Kuenzler www.claudiokuenzler.com		#
# Purpose:      Monitor IBM System Storage TS Tape Libraries		#
# Compatible:	TS3100, TS3200						#
# License: 	GPLv2							#
# History:                                                              #
# 20120316	Finished first version (my very first perl script, yay!)#
# 20120822	Tape Drive needs cleaning with different code (22)	#
# 20120901	Different approach to check for cleaning state		#
#########################################################################
my $version = '20120901';
#########################################################################
use strict;
use Getopt::Long;
use Net::SNMP;
use Switch;
#########################################################################
# Variable Declaration
my $hostname = '';
my $community = '';
my $model = '';
my $type = '';
my $help = '';
#my $warn = '';
#my $crit = '';
my $oid_base = '';
my $session = '';
my $error = '';
#########################################################################
# User Input
if ( @ARGV > 0 ) {
	GetOptions(
	'H=s' => \$hostname,
	'C:s' => \$community,
	'm=s' => \$model,
	't=s' => \$type,
	'help' => \$help,
	);
}
#########################################################################
# Check if user asks for help
if ( $help ne '' ) {
	help(); exit 0;
}

# Set community if not set by user
if ( $community eq '' ) {
	$community = "public";
}

# Check if model was set
if ( ($model ne "ts3100") && ($model ne "ts3200")) {
	print "Model must be either ts3100 or ts3200.\n";
	exit 2;
}
#########################################################################
# OID Definition
if ( $model eq "ts3100" ) {
	$oid_base = '.1.3.6.1.4.1.2.6.210';
}
else {
	$oid_base = '.1.3.6.1.4.1.2.6.211';
}
my $oid_hostname = ".1.3.6.1.2.1.1.5.0";
my $oid_uptime = ".1.3.6.1.2.1.1.3.0";
my $oid_productname = "$oid_base.1.1.0";
my $oid_vendorname = "$oid_base.1.3.0";
my $oid_productid = "$oid_base.3.1.1.8.1";
my $oid_serialnumber = "$oid_base.3.1.1.10.1";
my $oid_firmware = "$oid_base.3.1.1.9.1";
my $oid_globalstatus = "$oid_base.2.1.0";
my $oid_drivenumber = "$oid_base.3.1.1.11.1";
my $oid_cartridges = "$oid_base.3.1.1.12.1";
my $oid_faulterror = "$oid_base.3.1.1.22.1";
my $oid_faultseverity = "$oid_base.3.1.1.23.1";
my $oid_faultdesc = "$oid_base.3.1.1.24.1";
my $oid_cleanstate = "$oid_base.3.2.1.2"; 
#########################################################################
# Subs
sub help {
print "check_ibm_ts_tape.pl (c) 2012 Claudio Kuenzler (published under GPL License)
Version: $version\n
Usage: ./check_ibm_ts_tape.pl -H host [-C community] -m model -t checktype\n
Options: 
-H\tHostname or IP address of tape library.
-C\tSNMP community name (if not set, public will be used).
-m\tModel of the tape library. Must be either ts3100 or ts3200.
-t\tType to check. See below for valid types.
--help\tShow this help/usage.\n
Check Types:
info -> Show basic information of the tape library (hostname, serial number, etc)
status -> Checks the current status and outputs error codes if status is not ok
clean -> Checks all drives of tape library if cleaning is required\n";
}
#########################################################################
# SNMP Connection
($session,$error) = Net::SNMP->session(
			-hostname => $hostname,
			-community => $community,
			-version => 1,
			);
#########################################################################
# Plugin Checks
switch ($type) {
case "info" {
	my @oidlist = ($oid_hostname, $oid_productname, $oid_vendorname, $oid_productid, $oid_serialnumber, $oid_firmware);
	my $result = $session->get_request(-varbindlist => \@oidlist);
	
	if (!defined($result)) {
		printf("ERROR: Description table : %s.\n", $session->error);
		if ($session->error =~ m/noSuchName/ || $session->error =~ m/does not exist/) {
			print "Are you really sure the target host is a $model???!\n";
		}
		$session->close;
		exit 2;
	}

	my $hostname = $$result{$oid_hostname};
	my $vendorname = $$result{$oid_vendorname};
	$vendorname =~ s/\s+$//;
	my $productname = $$result{$oid_productname};
	my $productid = $$result{$oid_productid};
	$productid =~ s/\s+$//;
	my $serialnumber = $$result{$oid_serialnumber};
	my $firmware = $$result{$oid_firmware};

	print "$hostname ($vendorname $productname) - Product-No: $productid - S/N: $serialnumber - running on Firmware $firmware\n";
	exit 0;
}
case "status" {
	my @oidlist = ($oid_globalstatus, $oid_faulterror, $oid_faultdesc);
	my $result = $session->get_request(-varbindlist => \@oidlist);
        
	if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                if ($session->error =~ m/noSuchName/ || $session->error =~ m/does not exist/) {
                        print "Are you really sure the target host is a $model???!\n";
                }
                $session->close;
                exit 2;
        }

	my $globalstatus = $$result{$oid_globalstatus};
	my $faulterror = $$result{$oid_faulterror};
	my $faultdesc = $$result{$oid_faultdesc};

	switch ($globalstatus) {
		case 1 { print "$model WARNING - Current status is: other - $faultdesc (error code: $faulterror)\n"; exit 1; }
		case 2 { print "$model WARNING - Current status is: unknown - $faultdesc (error code: $faulterror)\n"; exit 1; }
		case 3 { print "$model OK - Current status is: ok\n"; exit 0; }
		case 4 { print "$model WARNING - Current status is: non-critical - $faultdesc (error code: $faulterror)\n"; exit 1; }
		case 5 { print "$model CRITICAL - Current status is: critical - $faultdesc (error code: $faulterror)\n"; exit 2; }
		case 6 { print "$model CRITICAL - Current status is: non-recoverable - $faultdesc (error code: $faulterror)\n"; exit 2; }
		else { print "$model UNKNOWN - Unknown status code\n"; exit 3; }
	}
}
case "clean" {
        my $result = $session->get_table(-baseoid => $oid_cleanstate);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                if ($session->error =~ m/noSuchName/ || $session->error =~ m/does not exist/) {
                        print "Are you really sure the target host is a $model???!\n";
                }
                $session->close;
                exit 2;
        }

	my %value = %{$result};
	my $key;
	my $drivestoclean = 0;
	
	foreach $key (keys %{$result}) {
		#print "$value{$key}\n"; # debug
		if ($value{$key} == 34) {
			$drivestoclean = $drivestoclean + 1;	
		}
	}
	
	if ($drivestoclean > 0) {
		print "$model WARNING - $drivestoclean tape drive needs to be cleaned\n";
		exit 1;
	}
	else {	print "$model OK - All tape drives are clean\n";
		exit 0;
	}

}
else { 
	print "Error: No type given. What do you want to check?\n";
	exit 2;
}

}
#########################################################################
# Close SNMP Session
$session->close(); 

print "UNKNOWN - The script should have exited before this point\n";
exit 3
