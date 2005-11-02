package eSTAR::RAPTOR::Util;

=head1 NAME

eSTAR::RAPTOR::Util - RAPTOR specific utility routines

=head1 SYNOPSIS

  use eSTAR::RAPTOR::Util
    
=head1 DESCRIPTION

This module contains a simple utility routines specific to RAPTOR.

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
use eSTAR::Constants qw /:all/;
use eSTAR::Logging;
use eSTAR::Process;
use eSTAR::Config;
use eSTAR::Error qw /:try/;
use Astro::VO::VOEvent;

@ISA = qw/Exporter/;
@EXPORT_OK = qw/ store_voevent /;

'$Revision: 1.3 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

sub store_voevent {
   my $message = shift;

   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
   my $config = eSTAR::Config::get_reference();
   my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
  
   my $object = new Astro::VO::VOEvent();
   my $id = $object->determine_id( $message );
   unless ( exists $id && defined $id && $id ne "" ) {
      $log->warn( "Warning: \$id is undefined, not writing event file");
      return undef;                               
   }
 
   $log->debug( "Storing event $id in " . $state_dir );   
   my $file = File::Spec->catfile( $state_dir, "$id.xml");
           
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


=back

=head1 REVISION

$Id: Util.pm,v 1.3 2005/11/02 01:43:27 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
