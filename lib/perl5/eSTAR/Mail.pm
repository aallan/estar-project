package eSTAR::Mail;

=head1 NAME

eSTAR::Mail - email related routines

=head1 SYNOPSIS

  use eSTAR::Mail
    
=head1 DESCRIPTION

This module contains a simple utility routines related to email.

=cut

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT_OK @ISA /;

use Data::Dumper;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT :flock);
use Net::SMTP;
use Config::Simple;
use Config::IniFiles;

use eSTAR::Constants qw /:all/;
use eSTAR::Logging;
use eSTAR::Process;
use eSTAR::Config;
use eSTAR::Error qw /:try/;
use eSTAR::Util;

@ISA = qw/Exporter/;
@EXPORT_OK = qw/ send_mail /;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);


sub send_mail {
   my $to = shift;
   my $to_name = shift;
   my $from = shift;
   my $subject = shift;
   my $body = shift;

   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
   my $config = eSTAR::Config::get_reference();
 
  
   $log->debug( "Sending mail to $real_name <$email_address>" ); 
   
   my $smtp = new Net::SMTP( 
                     Host    => $config->get_option("mailhost.name"),
                     Hello   => $config->get_option("mailhost.domain"),
                     Timeout => $config->get_option("mailhost.timeout"),
                     Debug   => $config->get_option("mailhost.debug")  );   
   
   if ( $@ ) {
     $log->error("Error: $@");
   } else {

     $log->debug( "Talking to mailserver..." );
                    
     $smtp->mail('allan@jach.hawaii.edu');
     $smtp->to( $parsed->email() );

     $smtp->data();
     $smtp->datasend("To: $to_name <$to>\n" );
     $smtp->datasend("From: eSTAR Project <$from>\n");
     $smtp->datasend("Subject: $subject\n");
     $smtp->datasend("\n");
     $smtp->datasend( $body );

     $smtp->quit;
  
     $log->debug( "Conneciton closed..." );
   
   }   
   
   
};



=back

=head1 REVISION

$Id: Mail.pm,v 1.1 2005/02/15 15:44:41 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2005 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
