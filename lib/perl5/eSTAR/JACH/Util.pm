package eSTAR::JACH::Util;

=head1 NAME

eSTAR::JACH::Util - JAC specific utility routines

=head1 SYNOPSIS

  use eSTAR::JACH::Util
    
=head1 DESCRIPTION

This module contains a simple utility routines specific to the JAC.

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

@ISA = qw/Exporter/;
@EXPORT_OK = qw/ current_instrument /;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);


sub current_instrument {
   my $telescope = shift;
   
   my $log = eSTAR::Logging::get_reference();
   
   my $file = File::Spec->catfile( $ENV{'ESTAR_INST_TYPE'}, 
                                   lc($telescope), "instrument.xml" );
   
   #my $file = "./instrument.xml";
   
   my $instrument = undef;
                                   
   $log->debug("Trying to access current instrument file");
   unless ( open ( INST, "<$file" ) ) {
      $log->warn("Warning: File $file not found");
      return undef;
   } else {
      unless ( flock( INST, LOCK_EX ) ) {
         $log->warn("Warning: unable to acquire exclusive lock: $!");
         return undef;
      } else {
         
         my $xml = undef;
         {
            $log->debug("Acquiring exclusive lock...");
            undef $/;
            $xml = <INST>;
            close (INST);         
            $log->debug("Freeing flock()...");
         
         } # naked block to confine the undef'ing of $/
         
         my $parser = new XML::Parser( Style            => 'Tree',
                                       ProtocolEncoding => 'US-ASCII' );
         my $document = $parser->parse( $xml );
         $instrument = ${${${$document}[1]}[0]}{"name"};
          
         
      } 
      
      return $instrument; 
      
   }     
   
};



=back

=head1 REVISION

$Id: Util.pm,v 1.1 2005/03/22 22:06:23 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
