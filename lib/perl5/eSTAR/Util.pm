package eSTAR::Util;

=head1 NAME

eSTAR::Util - utility routines

=head1 SYNOPSIS

  use eSTAR::Util
    
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
use eSTAR::Error qw /:try/;

@ISA = qw/Exporter/;
@EXPORT_OK = qw/ make_cookie make_id freeze thaw melt query_simbad/;

'$Revision: 1.9 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

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

sub make_id {

   my $log = eSTAR::Logging::get_reference();
   
   # CONTEXT FILE
   # ------------
   my $process = eSTAR::Process::get_reference();
   my $context_file = File::Spec->catfile( Config::User->Home(), '.estar', 
                                    $process->get_process(), 'contexts.dat' );

   # open (or create) the options file
   $log->debug("Reading agent context file from $context_file");
   my $CONTEXT = new Config::Simple( syntax   =>'ini', 
                                     mode     => O_RDWR|O_CREAT);

   unless ( defined $CONTEXT ) {
      # can't read/write to state file, scream and shout!
      my $error = $Config::Simple::errstr;
      $log->error("Error: " . chomp($error));
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);            
   }  

   # if it exists read the current contents in...
   if ( open ( CONFIG, "$context_file" ) ) {
      close( CONFIG );
      $CONTEXT->read( $context_file );
   }   
        
   # UNIQUE ID
   # ---------
   
   # generate a unique context ID, increment every time this routine is 
   # called and save immediately, therefore we should never duplicate ID's, 
   # of course we'll eventually run out of int's...
   my $number = $CONTEXT->param( 'context.unique_number' ); 
 
   if ( $number eq '' ) {
      # $number is not defined correctly (first ever observation?)
      $CONTEXT->param( 'context.unique_number', 0 );
      $number = 0; 
   } 
  
   # build string portion of identity
   my $version = $process->get_version();
   $version =~ s/\./-/g;
   
   my $string = ':WFCAM:v' . $version . 
                ':run#'    . get_state(  'mining.unique_process' ) .
                ':user#'   . get_option( 'user.user_name' );   
             
   # increment ID number
   $number = $number + 1;
   $CONTEXT->param( 'context.unique_number', $number );
   
   $log->debug('Incrementing context number to ' . $number);
     
   # commit ID stuff to CONTEXT file
   my $status = $CONTEXT->write( $context_file );
   unless ( defined $status ) {
      my $error = $Config::Simple::errstr;
      $log->error("Error: " . chomp($error));
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
   } else {    
      $log->debug('Generated ID: updated ' . $context_file ) ;
   }
   
   # Generate IDENTITY STRING
   my $id;   
  
   # format $number
   if ( length($number) == 1 ) {
       $id = '00000' . $number;
   } elsif ( length($number) == 2 ) {
       $id = '0000' . $number;
   } elsif ( length($number) == 3 ) {
       $id = '000' . $number;
   } elsif ( length($number) == 4 ) {
       $id = '00' . $number;
   } elsif ( length($number) == 5 ) {
       $id = '0' . $number;
   } else {
       $id = $number;
   }
   $id = $id . $string;
   $log->debug('ID = ' . $id);
      
   return $id;
}

sub freeze {
   my $id = shift;
   my $object = shift;

   my $log = eSTAR::Logging::get_reference();
      
   # RE-SERIALISE OBJECT
   # ===================
   my $process = eSTAR::Process::get_reference();
   my $state_dir = File::Spec->catdir( 
       Config::User->Home(), ".estar", $process->get_process(), "state");  
   
   $log->debug( "Serialising \$object ($id) to " . $state_dir );   
   
   my $file = File::Spec->catfile( $state_dir, $id);
           
   # write the observation object to disk.
   unless ( open ( SERIAL, "+>$file" )) {
      # check for errors, theoretically if we can't temporarily write to
      # the state directory this is no great loss as we'll create a fresh
      # observation object in the handle_rtml() routine if the unique id
      # of the object isn't known (i.e. it doesn't exist as a file in
      # the state directory)
      $log->warn( "Warning: Unable to serialise \$object");
      $log->warn( "Warning: Can not write to "  . $state_dir); 
                         
      return ESTAR__ERROR                               
   } else {
      unless ( flock( SERIAL, LOCK_EX ) ) {
         $log->warn("Warning: unable to acquire exclusive lock: $!");
         return undef;
      } else {
         $log->debug("Acquiring exclusive lock...");
      } 
      
      # serialise the object
      my $dumper = new Data::Dumper([$object], [qw($object)]  );      
      my $string = $dumper->Dump( );
      print SERIAL $string;
      close(SERIAL);  
      $log->debug("Freeing flock()...");
        
   }   
   
   return ESTAR__OK;
   
}

sub thaw {
   my $id = shift;

   my $log = eSTAR::Logging::get_reference();
   my $object;
   
   # check we actually have an $id
   return undef unless defined $id;
   
   # DE-SERIALISE OBJECT
   # ===================
   my $process = eSTAR::Process::get_reference();
   my $state_dir = File::Spec->catdir( 
       Config::User->Home(), ".estar", $process->get_process(), "state");  
        
   # Return any previous data from persistant store in the state directory
   my $observation_object;
   
   $log->debug("Trying to restore \$object");
   my $file = File::Spec->catfile( $state_dir, $id );
   unless ( open ( SERIAL, "<$file" ) ) {
      $log->warn("Warning: Unique ID not in state directory");
      return undef;
   } else {
      unless ( flock( SERIAL, LOCK_EX ) ) {
         $log->warn("Warning: unable to acquire exclusive lock: $!");
         return undef;
      } else {
         $log->debug("Acquiring exclusive lock...");
      } 
      
      # deserialise the object  
      undef $/;
      my $string = <SERIAL>;
      close (SERIAL);
      $log->debug("Freeing flock()...");
      $object = eval $string;
      $log->debug( "Restored object $id");
   }    
   return $object;
}


sub melt {
   my $id = shift;   
   my $log = eSTAR::Logging::get_reference();
   
   # DELETE OBJECT
   # =============
   my $process = eSTAR::Process::get_reference();
   my $state_dir = File::Spec->catdir( 
       Config::User->Home(), ".estar", $process->get_process(), "state");  
   
   $log->debug( "Removing \$object ($id) from " . $state_dir );   
   
   my $file = File::Spec->catfile( $state_dir, $id);
           
   # delete the object
   unless ( unlink $file ) {
      $log->warn( "Warning: Unable to unlink $file");
      return ESTAR__ERROR;
   }   
   
   $log->debug( "Unlinked $file");
   
   # good status
   return ESTAR__OK;
   
}

# Query SIMBAD by target
sub query_simbad {
   my $target = shift;
   

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
   
   $log->debug( "Called eSTAR::Util::query_simbad()..." );


   my $proxy;
   unless ( get_option("connection.proxy") eq "NONE" ) {
      $proxy = get_option("connection.proxy");
   }
      
   $log->warn( "Warning: Using deprecated Astro::SIMBAD module..." );
   my $simbad_query = new Astro::SIMBAD::Query( 
                         Target  => $target,
                         Timeout => get_option( "connection.timeout" ),
                         Proxy   => $proxy,
                         URL     => get_option( "simbad.url" ) );
                         
   $log->debug( "Contacting CDS SIMBAD (". $simbad_query->url() . ")..."  );
 
   # Throw an eSTAR::Error::FatalError if we have problems
   my $simbad_result;
   eval { $simbad_result = $simbad_query->querydb(); };
   if ( $@ ) {
      $log->error( "Error: Unable to contact CDS SIMBAD..." );
      return undef;
   }   

   $log->debug( "Retrieved result..." );
   return $simbad_result;
};



=back

=head1 REVISION

$Id: Util.pm,v 1.9 2005/01/11 01:41:25 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
