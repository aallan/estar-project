package eSTAR::Util;

=head1 NAME

eSTAR::Util - utility routines

=head1 SYNOPSIS

  use eSTAR::Util
  
  freeze()
  thaw()
  make_cookie()
  
=head1 DESCRIPTION

This module contains utility routines

=cut

use strict;
use warnings;

require Exporter;

use vars qw/$VERSION @EXPORT @ISA /;

use File::Spec;
use Data::Dumper;
use Fcntl ':flock';
use Digest::MD5 'md5_hex';
use eSTAR::Constants qw/:all/;

@ISA = qw/Exporter/;
@EXPORT = qw/freeze thaw melt make_cookie/;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);


sub thaw {
   my $id = shift;
   
   # check we actually have an $id
   return undef unless defined $id;
   
   # DE-SERIALISE OBJECT
   # ===================
   my $state_dir = File::Spec->catdir( 
       Config::User->Home(), ".estar", $main::process, "state");  
        
   # Return any previous data from persistant store in the state directory
   my $observation_object;
   
   $main::log->debug("Trying to restore \$observation_object");
   my $file = File::Spec->catfile( $state_dir, $id );
   unless ( open ( SERIAL, "<$file" ) ) {
      $main::log->warn("Warning: Unique ID not in state directory");
      return undef;
   } else {
      unless ( flock( SERIAL, LOCK_EX ) ) {
         $main::log->warn("Warning: unable to acquire exclusive lock: $!");
         return undef;
      } else {
         $main::log->debug("Acquiring exclusive lock...");
      } 
      
      # deserialise the object  
      undef $/;
      my $string = <SERIAL>;
      close (SERIAL);
      $main::log->debug("Freeing flock()...");
      $observation_object = eval $string;
      $main::log->debug( "Restored observation " . $observation_object->id());
   }    
   return $observation_object;
}


sub melt {
   my $observation_object = shift;   
   my $id = $observation_object->id();
   
   # DELETE OBJECT
   # =============
   my $state_dir = File::Spec->catdir( 
       Config::User->Home(), ".estar", $main::process, "state");  
   
   $main::log->debug( "Removing \$observation_object from " . $state_dir );   
   
   my $file = File::Spec->catfile( $state_dir, $id);
           
   # delete the object
   unless ( unlink $file ) {
      $main::log->warn( "Warning: Unable to unlink $file");
      return ESTAR__ERROR;
   }   
   
   $main::log->debug( "Unlinked $file");
   
   # good status
   return ESTAR__OK;
   
}

sub freeze {
   my $observation_object = shift;
   
   my $id = $observation_object->id();
   
   # RE-SERIALISE OBJECT
   # ===================
   my $state_dir = File::Spec->catdir( 
       Config::User->Home(), ".estar", $main::process, "state");  
   
   $main::log->debug( "Serialising \$observation_object to " . $state_dir );   
   
   my $file = File::Spec->catfile( $state_dir, $id);
           
   # write the observation object to disk. Lets use a DBM backend next
   # time shall we?
   unless ( open ( SERIAL, "+>$file" )) {
      # check for errors, theoretically if we can't temporarily write to
      # the state directory this is no great loss as we'll create a fresh
      # observation object in the handle_rtml() routine if the unique id
      # of the object isn't known (i.e. it doesn't exist as a file in
      # the state directory)
      $main::log->warn( "Warning: Unable to serialise observation_object");
      $main::log->warn( "Warning: Can not write to "  . $state_dir); 
                         
      return ESTAR__ERROR                               
   } else {
      unless ( flock( SERIAL, LOCK_EX ) ) {
         $main::log->warn("Warning: unable to acquire exclusive lock: $!");
         return undef;
      } else {
         $main::log->debug("Acquiring exclusive lock...");
      } 
      
      # serialise the object
      my $dumper = new Data::Dumper([$observation_object],
                                       [qw($observation_object)]  );
      
      # a quick hack                                 
      $main::log->debug("Using regular expressions to fix Astro::Catalog...");
      
      my $string = $dumper->Dump( );
      
      $string =~ 
         s/\s*\$observation_object->\{'CATALOG'}\[0]{'ALLSTARS'}\[\w+],\n//g;
      $string =~ 
         s/\s*\$observation_object->\{'CATALOG'}\[0]{'ALLSTARS'}\[\w+]\n//g;
      $string =~ 
         s/'CURRENT' => \[\n\s*]/'CURRENT' => undef/g;   
      $string =~ 
         s/'CURRENT' => \[\s*]/'CURRENT' => undef/g;   
         
                                       
      print SERIAL $string;
      close(SERIAL);  
      $main::log->debug("Freeing flock()...");
        
   }   
   
   return ESTAR__OK;
   
}


# This is the code that is used to generate cookies based on the user
# name and password. It is NOT cryptographically sound, it is just a
# simple form of obfuscation, used as an example. Should be replaced
# before system goes live. (AA 06-MAY-2003)
sub make_cookie {
   my ($user, $passwd) = @_;
   my $cookie = $user . "::" . md5_hex($passwd);
   $cookie =~ s/(.)/sprintf("%%%02x", ord($1))/ge;
   $cookie =~ s/%/%25/g;
   $cookie;
}

=back

=head1 REVISION

$Id: Util.pm,v 1.1 2004/02/18 22:06:09 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
