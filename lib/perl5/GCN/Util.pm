package GCN::Util;

=head1 NAME

GCN::Util - utility routines

=head1 SYNOPSIS

  use GCN::Util
    
=head1 DESCRIPTION

This module contains a simple utility routines.

=cut

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT_OK @ISA /;

use Data::Dumper;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT :flock);
use Config::Simple;
use Config::IniFiles;
use eSTAR::Constants qw /:all/;
use eSTAR::Logging;
use eSTAR::Process;
use eSTAR::Config;
use eSTAR::Error qw /:try/;

@ISA = qw/Exporter/;
@EXPORT_OK = qw/ convert_to_sextuplets /;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);


sub convert_to_sextuplets {
   my ($ra, $dec, $error ) = @_;
   
   # convert RA to sextuplets
   my $ra_deg = $ra/10000.0;
   $ra_deg = $ra_deg/15.0;
   my $period = index( $ra_deg, ".");
   my $length = length( $ra_deg );
   my $ra_min = substr( $ra_deg, -($length-$period-1));
   $ra_min = "0." . $ra_min;
   $ra_min = $ra_min*60.0;  
   $ra_deg = substr( $ra_deg, 0, $period);
   $period = index( $ra_min, ".");
   $length = length( $ra_min );         
   my $ra_sec = substr( $ra_min, -($length-$period-1));
   $ra_sec = "0." . $ra_sec;
   $ra_sec = $ra_sec*60.0;
   $ra_min = substr( $ra_min, 0, $period); 
   
   $ra = "$ra_deg $ra_min $ra_sec";
   
   # convert Dec to sextuplets
   my $dec_deg = $dec;
   $dec_deg = $dec_deg/10000.0;
   my $sign = "pos";
   if ( $dec_deg =~ "-" ) {
      $dec_deg =~ s/-//;
      $sign = "neg";
   }
   $period = index( $dec_deg, ".");
   $length = length( $dec_deg );
   my $dec_min = substr( $dec_deg, -($length-$period-1));
   $dec_min = "0." . $dec_min;
   $dec_min = $dec_min*60.0;
   $dec_deg = substr( $dec_deg, 0, $period);
   $period = index( $dec_min, ".");
   $length = length( $dec_min );
   my $dec_sec = substr( $dec_min, -($length-$period-1));
   $dec_sec = "0." . $dec_sec;
   $dec_sec = $dec_sec*60.0;
   $dec_min = substr( $dec_min, 0, $period);
   if( $sign eq "neg" ) {
      $dec_deg = "-" . $dec_deg;
   }
   
   $dec = "$dec_deg $dec_min $dec_sec";                 

   # convert error to arcmin
   $error = ($error*60.0)/10000.0;  
  
   return ( $ra, $dec, $error );
}

=back

=head1 REVISION

$Id: Util.pm,v 1.1 2005/02/07 21:36:50 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
