#!/usr/bin/perl -w
#########################################################################
# Script:       check_ibm_ts_tape.pl					#
# Author:       Claudio Kuenzler www.claudiokuenzler.com		#
# Purpose:      Monitor IBM System Storage TS Tape Libraries		#
# Compatible:	TS3100, TS3200,TS3310					#
# License: 	GPLv2							#
# History:                                                              #
# 20120316	Finished first version (my very first perl script, yay!)#
# 20120822	Tape Drive needs cleaning with different code (22)	#
# 20120901	Different approach to check for cleaning state		#
# 20140826	Nick Jeffrey - add support for TS3310 			#
# 20140826	Move all variable declaration to top -remove excess "my"#
#########################################################################
my $version = '20140826';
#########################################################################
use strict;
use Getopt::Long;
use Net::SNMP;
use Switch;
#########################################################################
# Variable Declaration
my ($oid_base,$oid_hostname,$oid_uptime,$oid_productname,$oid_vendorname);
my ($oid_productid,$oid_serialnumber,$oid_firmware,$oid_globalstatus);
my ($oid_drivenumber,$oid_cartridges,$oid_faulterror);
my ($oid_faultseverity,$oid_faultdesc,$oid_cleanstate);
my ($oid_online_p,$oid_online_l,$oid_iodoor,$oid_driveonline,$oid_robotonline);
my $hostname = '';
my $community = '';
my $model = '';
my $type = '';
my $help = '';
#my $warn = '';
#my $crit = '';
my $session = '';
my $error = '';
my $vendorname = '';
my $productname = '';
my $productid = '';
my $serialnumber = '';
my $firmware = '';
my (@oidlist,$result);
my ($globalstatus,$faulterror,$faultdesc);
my (%value,$key,$drivestoclean);
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
if ( ($model ne "ts3100") && ($model ne "ts3200") && ($model ne "ts3310") ) {
	print "Model must be either ts3100 or ts3200 or ts3310.\n";
	exit 2;
}
#########################################################################
# OID Definition
if ( $model eq "ts3100" ) {
	$oid_base             = '.1.3.6.1.4.1.2.6.210';		#unique OID for ts3100
        $oid_hostname      = ".1.3.6.1.2.1.1.5.0";
        $oid_uptime        = ".1.3.6.1.2.1.1.3.0";
        $oid_productname   = "$oid_base.1.1.0";
        $oid_vendorname    = "$oid_base.1.3.0";
        $oid_productid     = "$oid_base.3.1.1.8.1";
        $oid_serialnumber  = "$oid_base.3.1.1.10.1";
        $oid_firmware      = "$oid_base.3.1.1.9.1";
        $oid_globalstatus  = "$oid_base.2.1.0";
        $oid_drivenumber   = "$oid_base.3.1.1.11.1";
        $oid_cartridges    = "$oid_base.3.1.1.12.1";
        $oid_faulterror    = "$oid_base.3.1.1.22.1";
        $oid_faultseverity = "$oid_base.3.1.1.23.1";
        $oid_faultdesc     = "$oid_base.3.1.1.24.1";
        $oid_cleanstate    = "$oid_base.3.2.1.2"; 
}
if ( $model eq "ts3200" ) {
	$oid_base             = '.1.3.6.1.4.1.2.6.211';		#unique OID for ts3200
        $oid_hostname      = ".1.3.6.1.2.1.1.5.0";
        $oid_uptime        = ".1.3.6.1.2.1.1.3.0";
        $oid_productname   = "$oid_base.1.1.0";
        $oid_vendorname    = "$oid_base.1.3.0";
        $oid_productid     = "$oid_base.3.1.1.8.1";
        $oid_serialnumber  = "$oid_base.3.1.1.10.1";
        $oid_firmware      = "$oid_base.3.1.1.9.1";
        $oid_globalstatus  = "$oid_base.2.1.0";
        $oid_drivenumber   = "$oid_base.3.1.1.11.1";
        $oid_cartridges    = "$oid_base.3.1.1.12.1";
        $oid_faulterror    = "$oid_base.3.1.1.22.1";
        $oid_faultseverity = "$oid_base.3.1.1.23.1";
        $oid_faultdesc     = "$oid_base.3.1.1.24.1";
        $oid_cleanstate    = "$oid_base.3.2.1.2"; 
}
if ( $model eq "ts3310" ) {
	$oid_base = '.1.3.6.1.4.1.3764.1.10.10';		#unique OID for ts3310
        $oid_hostname      = ".1.3.6.1.2.1.1.5.0";
        $oid_uptime        = ".1.3.6.1.2.1.1.3.0";
        $oid_productname   = "$oid_base.1.10.0";
        $oid_vendorname    = "$oid_base.1.4.0";
        $oid_productid     = "$oid_base.1.7.0";
        $oid_serialnumber  = "$oid_base.1.5.0";
        $oid_firmware      = "$oid_base.1.11.0";  
        $oid_globalstatus  = "$oid_base.1.8.0";    		# libraryGlobalStatus  1=good 2=? 4=? 8=?
        $oid_drivenumber   = "$oid_base.3.1.1.11.1";		#not used anywhere else in this script
        $oid_cartridges    = "$oid_base.3.1.1.12.1"; 		#not used anywhere else in this script
        $oid_faulterror    = "$oid_base.11.1.0"; 		#OID not used for this model.  Dummy in overallPhDriveReadinessStatus  1=online 
        $oid_faultseverity = "$oid_base.11.1.0";		#OID not used for this model.  Dummy in overallPhDriveReadinessStatus  1=online
        $oid_faultdesc     = "$oid_base.11.1.0";		#OID not used for this model.  Dummy in overallPhDriveReadinessStatus  1=online
        $oid_cleanstate    = "$oid_base.11.3.1.12";   		# CleaningStatus 1=required 2=notRequired 3=immediate
        #$oid_online_p     = "$oid_base.14.1.0"; 		# physical library 1=online 0=offline
        #$oid_online_l     = "$oid_base.13.2.1.8"; 		# logical library 1=online 0=offline  (may be multiple logical libraries)
        #$oid_iodoor       = "$oid_base.14.3.0"; 		# I/O station door   1=opened 2=closedAndLocked 3=closedAndUnLocked
        #$oid_driveonline  = "$oid_base.11.3.1.10"; 		# tape drives online/offline 1=online 2=offline
        #$oid_robotonline  = "$oid_base.14.30.2.0"; 		# robotic arm ready 1=ready 0=?
}
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
info   -> Show basic information of the tape library (hostname, serial number, etc)
status -> Checks the current status and outputs error codes if status is not ok
clean  -> Checks all drives of tape library if cleaning is required\n";
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
	@oidlist = ($oid_hostname, $oid_productname, $oid_vendorname, $oid_productid, $oid_serialnumber, $oid_firmware);
	$result = $session->get_request(-varbindlist => \@oidlist);
	
	if (!defined($result)) {
		printf("ERROR: Description table : %s.\n", $session->error);
		if ($session->error =~ m/noSuchName/ || $session->error =~ m/does not exist/) {
			print "Are you really sure the target host is a $model???!\n";
		}
		$session->close;
		exit 2;
	}

	$hostname = $$result{$oid_hostname};
	$vendorname = $$result{$oid_vendorname};
	$vendorname =~ s/\s+$//;
	$productname = $$result{$oid_productname};
	$productid = $$result{$oid_productid};
	$productid =~ s/\s+$//;
	$serialnumber = $$result{$oid_serialnumber};
	$firmware = $$result{$oid_firmware};

	print "$hostname ($vendorname $productname) - Product-No: $productid - S/N: $serialnumber - running on Firmware $firmware\n";
	exit 0;
}
case "status" {
	@oidlist = ($oid_globalstatus, $oid_faulterror, $oid_faultdesc);
	$result = $session->get_request(-varbindlist => \@oidlist);
        
	if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                if ($session->error =~ m/noSuchName/ || $session->error =~ m/does not exist/) {
                        print "Are you really sure the target host is a $model???!\n";
                }
                $session->close;
                exit 2;
        }

	$globalstatus = $$result{$oid_globalstatus};
	$faulterror = $$result{$oid_faulterror};
	$faultdesc = $$result{$oid_faultdesc};

        if ( ($model eq "ts3100") || ($model eq "ts3200") ) {
	    switch ($globalstatus) {
		case 1 { print "$model WARNING - Current status is: other - $faultdesc (error code: $faulterror)\n"; exit 1; }
		case 2 { print "$model WARNING - Current status is: unknown - $faultdesc (error code: $faulterror)\n"; exit 1; }
		case 3 { print "$model OK - Current status is: ok\n"; exit 0; }
		case 4 { print "$model WARNING - Current status is: non-critical - $faultdesc (error code: $faulterror)\n"; exit 1; }
		case 5 { print "$model CRITICAL - Current status is: critical - $faultdesc (error code: $faulterror)\n"; exit 2; }
		case 6 { print "$model CRITICAL - Current status is: non-recoverable - $faultdesc (error code: $faulterror)\n"; exit 2; }
		else   { print "$model UNKNOWN - Unknown status code\n"; exit 3; }
	    }
        }
        if ( $model eq "ts3310" ) {
	    switch ($globalstatus) {
		case 1 { print "$model OK - Current status is: ok\n"; exit 0; }
		else   { print "$model UNKNOWN - Unknown status code\n"; exit 3; }
	    }
        }
}
case "clean" {
        $result = $session->get_table(-baseoid => $oid_cleanstate);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                if ($session->error =~ m/noSuchName/ || $session->error =~ m/does not exist/) {
                        print "Are you really sure the target host is a $model???!\n";
                }
                $session->close;
                exit 2;
        }

	%value = %{$result};
	#$key;
	$drivestoclean = 0;
	
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
