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
use Storable qw(nfreeze thaw dclone);;
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
@EXPORT_OK = 
      qw/ make_cookie make_id freeze thaw reheat melt query_simbad 
          fudge_message fudge_user fudge_project /;

'$Revision: 1.16 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

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
   my $config = eSTAR::Config::get_reference();
   my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
   
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
   my $config = eSTAR::Config::get_reference();
   my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
        
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

sub chill {
   my $object = shift;

   my $log = eSTAR::Logging::get_reference();
      
   # SERIALISE OBJECT
   # ================
   $log->debug( "Serialising \$object..." );   
   #my $dumper = new Data::Dumper([$object], [qw($object)]  );      
   #my $string = $dumper->Dump( );
   my $string = Storable::nfreeze( $object );
   
   return $string;
   
}

sub reheat {
   my $string = shift;
   
   my $log = eSTAR::Logging::get_reference();
   
   # check we actually have an $id
   return undef unless defined $string;
   
   # DE-SERIALISE OBJECT
   # ===================
   $log->debug("Trying to restore \$object");
   #my $object;
   #eval $string;
   my $object = Storable::thaw( $string );
   return $object;
}


sub melt {
   my $id = shift;   
   my $log = eSTAR::Logging::get_reference();
   
   # DELETE OBJECT
   # =============
   my $process = eSTAR::Process::get_reference();
   my $config = eSTAR::Config::get_reference();
   my $state_dir = File::Spec->catdir( $config->get_state_dir() );   
   
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

# grabs the origin host, port and identity of the message from the RTML

sub fudge_message {
   my $rtml = shift;
   my @message = split( /\n/, $rtml );


   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
      
   $log->debug("Called fudge_message()...");
   
   my ( $host, $port, $ident );
   foreach my $i ( 0 ... $#message ) {
     if ( $message[$i] =~ "<IntelligentAgent" ) {
        
        my ( $host_index, $port_index, $start_index, $last_index );
        
        # grab hostname
        if ( $message[$i] =~ 'host="' ) {
           $host_index = index( $message[$i], q/host=/ );
           $host = substr( $message[$i], $host_index, 
                                         length($message[$i])-$host_index );
           $start_index = index( $host, q/"/ );         
           $port_index = index( $host, q/port=/ );
           $host = substr( $host, $start_index+1, $port_index-$start_index-1 );
           $last_index = rindex( $host, q/"/ );         
           $host = substr( $host, 0, $last_index );
        } else {
           $host_index = index( $message[$i], q/host=/ );
           $host = substr( $message[$i], $host_index, 
                                         length($message[$i])-$host_index );
           $start_index = index( $host, q/=/ );         
           $port_index = index( $host, q/ / );
           $host = substr( $host, $start_index+1, $port_index-$start_index );
           $last_index = rindex( $host, q/"/ );         
           $host = substr( $host, 0, $last_index );        
        }  
        
        # grab port number
        if ( $message[$i] =~ 'port="' ) {
           $port_index = index( $message[$i], q/port=/ );
           $last_index = rindex( $message[$i], q/"/ );
           $port = substr( $message[$i], $port_index, $last_index-$port_index );
           $start_index = index( $port, q/"/ );
           $last_index = rindex( $message[$i], q/"/ );
           $port = substr( $port, $start_index+1, $last_index-$start_index-1 );
        } else {
           $port_index = index( $message[$i], q/port=/ );
           $last_index = rindex( $message[$i], '>' );
           $port = substr( $message[$i], $port_index, $last_index-$port_index );
           $start_index = index( $port, q/=/ );
           $last_index = index( $port, '>' );
           $port = substr( $port, $start_index+1, $last_index-$start_index-1 );
        }  
        $log->debug("Reply address: " . $host . ":" . $port);

        # grab unique identity
        my $tag_start = index( $rtml, q/<IntelligentAgent/ );
        my $tag_end = index( $rtml, q/<\/IntelligentAgent/ );
        
        $ident = substr( $rtml, $tag_start, $tag_end-$tag_start );
        my $quot_index = index ( $ident, q/>/ );
        $ident = substr( $ident, $quot_index+1, length($ident)-$quot_index);
        $ident =~ s/\n//g;
        $ident =~ s/\s+//g;

        $log->debug("Identifier: $ident");
        return ( $host, $port, $ident );

                    
     }   
   }
   
   return ( undef, undef, undef );
} 

sub fudge_user {
   my $rtml = shift;
   my $user = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
      
   my @message = split( /\n/, $rtml );
   
   $log->debug("Called fudge_user( $user )...");
   
   my $new_rtml = "";
   foreach my $i ( 0 ... $#message ) {
     if ( $message[$i] =~ "<User>" ) {
        if ( $message[$i] =~ "</User>" ) {
           $message[$i] = "<User>$user</User>";
        } else {
           my $error = "Unable to parse <User></User> field from document";
           throw eSTAR::Error::FatalError($error, ESTAR__FATAL); 
        }     
     }
     $new_rtml = $new_rtml . $message[$i] . "\n";
     
   }
   return $new_rtml;
}     


sub fudge_project {
   my $rtml = shift;
   my $project_id = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
   $log->debug("Called fudge_project( $project_id )...");
     
   my @message = split( /\n/, $rtml );
      
   my $new_rtml = "";
   foreach my $i ( 0 ... $#message ) {
     if ( $message[$i] =~ "<Project />" ) {  
        $message[$i] = "<Project>$project_id</Project>";
     } 
     $new_rtml = $new_rtml . $message[$i] . "\n";
   }
   
   return $new_rtml;
}

=back

=head1 REVISION

$Id: Util.pm,v 1.16 2005/06/30 21:42:03 aa Exp $

=head1 AUTHORS

Alasdair Allan E<lt>aa@astro.ex.ac.ukE<gt>

=head1 COPYRIGHT

Copyright (C) 2003 Particle Physics and Astronomy Research
Council. All Rights Reserved.

=cut

1;
