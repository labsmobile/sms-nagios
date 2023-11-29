#!/usr/bin/perl

#
# ============================== SUMMARY =====================================
#
# Program   : notify_sms.pl
# Version   : 1.4.2
# Date      : 03 Dec 2015
# Author    : Boris Vogel / LabsMobile
# Copyright : LabsMobile All rights reserved.
# Summary   : This plugin sends SMS alerts through the LabsMobile SMS API
# License   : ISC
#
# =========================== PROGRAM LICENSE =================================
#
# Copyright (c) LabsMobile 2014
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#
# ============================= MORE INFO ======================================
# 
# As released this plugin requires a LabsMobile account to send text
# messages.  To setup a LabsMobile account visit:
#   http://www.labsmobile.com
#
#
# ============================= SETUP NOTES ====================================
# 
# Copy this file to your Nagios plugin folder
# On a Centos install this is typically /usr/lib/nagios/libexec (32 bit) 
# or /usr/lib64/nagios/libexec (64 bit) other distributions may vary.
# Make sure you have SSL enabled. Run this otherwise:
# perl -MCPAN -e 'install Crypt::SSLeay'
# Testing. From the command line in the plugin folder run:
# ./notify-sms.pl -u yourusername -p yourpassword -t yournumber -f Nagios -m "bodge"
# replacing yourusername, yourpassword and yournumber with the appropriate values.
# 
#
# NAGIOS SETUP
#
# 1. Create the SMS notification commands.  (Commonly found in commands.cfg)
#    Don't forget to add your LabsMobile username and password. These can be placed 
#    in your commands instead of the API_USERNAME and API_PASSWORD given below
#    -f Nagios - you can change Nagios to a different "from" if you want.
#
# define command{
#       command_name    service-notify-by-sms
#       command_line    $USER1$/notify_sms.pl -u API_USERNAME -p API_PASSWORD -t $CONTACTPAGER$ -f Nagios -m "Service: $SERVICEDESC$\\nHost: $HOSTNAME$\\nAddress: $HOSTADDRESS$\\nState: $SERVICESTATE$\\nInfo: $SERVICEOUTPUT$\\nDate: $LONGDATETIME$"
# }
#
# define command{
#       command_name    host-notify-by-sms
#       command_line    $USER1$/notify_sms.pl -u API_USERNAME -p API_PASSWORD -t $CONTACTPAGER$ -f Nagios -m "Host $HOSTNAME$ is $HOSTSTATE$\\nInfo: $HOSTOUTPUT$\\nTime: $LONGDATETIME$"
# }
#
# 2. In your nagios contacts (Commonly found on contacts.cfg) add 
#    the SMS notification commands:
#
#    service_notification_commands      service-notify-by-sms
#    host_notification_commands         host-notify-by-sms
#
# 3. Add a pager number to your contacts, make sure it has the international 
#    prefix, e.g. 44 for UK or 1 for USA, without a leading 00 or +.
#
#    pager      447700900000  
#


use strict;
use Getopt::Long;
use LWP;
use URI::Escape;

my $version = '1.4.2';
my $verbose = undef;
my $key = undef;
my $password = undef;
my $to = undef;
my $username = undef;
my $password = undef;
my $res = undef;
my $substr = undef;
my $str = undef;
my $from = "Nagios";
my $message = undef;

sub print_version { print "$0: version $version\n"; exit(1); };
sub verb { my $t=shift; print "VERBOSE: ",$t,"\n" if defined($verbose) ; }
sub print_usage {
        print "Usage: $0 [-v] -u <username> -t <to> [-f <from>] -m <message>\n";
}

sub help {
        print "\nNotify by SMS Plugin ", $version, "\n";
        print " LabsMobile - http://www.labsmobile.com/\n\n";
        print_usage();
        print <<EOD;
-h, --help
        print this help message
-V, --version
        print version
-v, --verbose
        print extra debugging information
-u, --usernamme=USERNAME
        LabsMobile API Key
-p, --password=PASSWORD
        LabsMobile API Secret
-t, --to=TO
        mobile number to send SMS to in international format
-f, --from=FROM (Optional)
        string to send from (max 11 chars)
-m, --message=MESSAGE
        content of the text message
EOD
        exit(1);
}

sub check_options {
        Getopt::Long::Configure ("bundling");
        GetOptions(
                'v'     => \$verbose,           'verbose'       => \$verbose,
                'V'     => \&print_version,     'version'       => \&print_version,
                'h'     => \&help,              'help'          => \&help,
                'u=s'   => \$username,          'username=s'    => \$username,
                'p=s'   => \$password,          'password=s'    => \$password,
                't=s'   => \$to,                'to=s'          => \$to,
                'f=s'   => \$from,              'from=s'        => \$from,
                'm=s'   => \$message,           'message=s'     => \$message
        );

        if (!defined($username))
                { print "ERROR: No username defined!\n"; print_usage(); exit(1); }
        if (!defined($password))
                { print "ERROR: No password defined!\n"; print_usage(); exit(1); }
        if (!defined($to))
                { print "ERROR: No to defined!\n"; print_usage(); exit(1); }
        if (!defined($message))
                { print "ERROR: No message defined!\n"; print_usage(); exit(1); }

        if($to!~/^\d{7,15}$/) {
                { print "ERROR: Invalid to number!\n"; print_usage(); exit(1); }
        }
        verb "username = $username";
        verb "password = $password";
        verb "to = $to";
        verb "from = $from";
        verb "message = $message";
}

sub SendSMS {
        my $username = shift;
        my $password = shift;
        my $to = shift;
        my $from = shift;
        my $message = shift;

        # Convert "\n" to real newlines (Nagios seems to eat newlines).
        $message=~s/\\n/\n/g;

        # URL Encode parameters before making the HTTP POST
        $username   = uri_escape($username);
        $password   = uri_escape($password);
        $to         = uri_escape($to);
        $from       = uri_escape($from);
        $message    = uri_escape($message);

        my $result;
        
		my $baseurl = "https://api.labsmobile.com/get/send.php";
		my $getvars = "username=$username&password=$password&message=$message&msisdn=$to&sender=$from";

        verb("Get Data: ".$getvars);

		my $ua = LWP::UserAgent->new();
		$ua->timeout(5);
		$ua->agent('Nagios-SMS-Plugin/'.$version);
		my $res = $ua->get("$baseurl?$getvars");
		
		verb("GET Status: ".$res->status_line);
        verb("GET Response: ".$res->content);

		if (index($str, $substr) != -1) {
			print "$str contains $substr\n";
		} 

        if($res->is_success) {
                if(not index($res->content, "<code>0<")) {
                        print $res->content;
                        $result = 1;
                } else {
                        $result = 0;
                }
        } else {
                $result = 1;
                print $res->status_line;
        }

        return $result;
}


check_options();
my $send_result = SendSMS($username, $password, $to, $from, $message);

exit($send_result);