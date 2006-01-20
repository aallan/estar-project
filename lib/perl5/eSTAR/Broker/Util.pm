package eSTAR::Broker::Util;

=head1 NAME

eSTAR::Broker::Util - Broker specific utility routines

=head1 SYNOPSIS

  use eSTAR::Broker::Util
    
=head1 DESCRIPTION

This module contains a simple utility routines specific to Broker.

=cut

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT_OK @ISA /;

use Data::Dumper;
use Digest::MD5 'md5_hex';
use Fcntl qw(:DEFAULT :flock);
use File::Spec;
use XML::Parser;
use Time::localtime;
use DateTime;
use DateTime::Format::ISO8601;
use eSTAR::Constants qw /:all/;
use eSTAR::Logging;
use eSTAR::Process;
use eSTAR::Config;
use eSTAR::Error qw /:try/;
use Astro::VO::VOEvent;

@ISA = qw/Exporter/;
@EXPORT_OK = qw/ store_voevent time_iso time_rfc822 iso_to_rfc822 /;

'$Revision: 1.14 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

sub store_voevent {
   my $server = shift;
   my $message = shift;

   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
   my $config = eSTAR::Config::get_reference();
   my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
  
   my $object = new Astro::VO::VOEvent( XML => $message );
   my $id;
   eval { $id = $object->id(  ); };
   if ( $@ ) {
           $log->error( "Error: $@" );
   } 
   unless ( defined $id && $id ne "" ) {
      $log->warn( "Warning: \$id is undefined, not writing event file");
      return undef;                               
   }
   
   $log->debug( "Storing event $id in " . $state_dir );   

   $log->debug( "Splitting \$id..." );   
   my $idpath = $id;
   $idpath =~ s/#/\//;
   my @path = split( "/", $idpath );
   if ( $path[0] eq "ivo:" ) {
      splice @path, 0 , 1;
   }
   if ( $path[0] eq "" ) {
      splice @path, 0 , 1;
   }   
   
   # Build path to save file in... yuck!
   my $dir = File::Spec->catdir( $state_dir, $server );
   if ( opendir ( DIR, $dir ) ) {
      closedir DIR;   
   } else {
      mkdir $dir, 0755;
      if ( opendir ( DIR, $dir ) ) {
     	 closedir DIR;
      } else {
     	 $log->warn( "Warning: Unable to create $dir");
     	 return undef;  			     
      }      
   }
   
   foreach my $i ( 0 ... ($#path - 1) ) {
      if ( $path[$i] eq "" ) {
         next;
      }
      $dir = File::Spec->catdir( $dir, $path[$i] );
      
      if ( opendir ( DIR, $dir ) ) {
         closedir DIR;
         next;
      } else {
         $log->warn( "Warning: Creating $dir" );
         mkdir $dir, 0755;
         if ( opendir ( DIR, $dir ) ) {
            closedir DIR;
            next;
         } else {
            $log->warn( "Warning: Unable to create $dir");
            return undef;                               
         }
      }
   }   

   my $file = File::Spec->catfile( $dir, "$path[$#path].xml");
   $log->debug("Serialising to $file");
           
   # write the observation object to disk.
   unless ( open ( SERIAL, "+>$file" )) {
      $log->warn( "Warning: Unable to write file $file");
      return undef;                               
   } else {
      unless ( flock( SERIAL, LOCK_EX ) ) {
         $log->warn("Warning: unable to acquire exclusive lock: $!");
         return undef;
      } else {
         $log->debug("Acquiring exclusive lock...");
      } 
      
      print SERIAL $message;
      close(SERIAL);  
      $log->debug("Freeing flock()...");
        
   }   
   
   return $file;
   
}

sub time_iso {
   # ISO format 2006-01-05T08:00:00
   		     
   my $year = 1900 + localtime->year();
   
   my $month = localtime->mon() + 1;
   $month = "0$month" if $month < 10;
   
   my $day = localtime->mday();
   $day = "0$day" if $day < 10;
   
   my $hour = localtime->hour();
   $hour = "0$hour" if $hour < 10;
   
   my $min = localtime->min();
   $min = "0$min" if $min < 10;
   
   my $sec = localtime->sec();
   $sec = "0$sec" if $sec < 10;
   
   my $timestamp = $year ."-". $month ."-". $day ."T". 
   		   $hour .":". $min .":". $sec;

   return $timestamp;
}   

sub time_rfc822 {
   # ctime() returns:	   Mon Dec 19 20:34:02 2005
   # need RFC822 format:   Wed, 02 Oct 2002 08:00:00 EST
 
   my @date = split " ", ctime();
   my $rfc822 = $date[0] . ", " . $date[2] . " " . $date[1] . 
   	   " " . $date[4] . " " . $date[3] . " GMT";

   return $rfc822;
}

sub iso_to_rfc822 {
   my $iso = shift;
   my $date = DateTime::Format::ISO8601->parse_datetime( $iso );
   my $rfc822 = $date->day_abbr() . ", " .
             $date->day_of_month() . " " . $date->month_abbr() . 
   	   " " . $date->year() . " " . 
	   $date->hour() .":" . $date->min() .":". $date->sec() . " GMT";
   return $rfc822; 		    
}

=back

=head1 REVISION

$Id: Util.pm,v 1.14 2006/01/20 09:24:18 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
