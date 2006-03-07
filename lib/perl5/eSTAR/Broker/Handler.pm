package eSTAR::Broker::Handler;

# Basic handler class for SOAP requests for the User Agent. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR_PERL5LIB"};     

use strict;
use subs qw( new set_user ping echo handle_voevent get_option
             set_option kill);

#
# Threading code (ithreads)
# 
use threads;
use threads::shared;

#
# General modules
#
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use Time::localtime;
use Sys::Hostname;
#use Net::Domain qw(hostname hostdomain);
use Config::Simple;
use Config::User;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);
use Net::FTP;

# 
# eSTAR modules
#
use eSTAR::SOAP::User;
use eSTAR::Logging;
use eSTAR::Observation;
use eSTAR::Constants qw/:all/;
use eSTAR::Util;
use eSTAR::Mail;
use eSTAR::Config;
use eSTAR::Broker::Util;
use eSTAR::Broker::Running;

#
# Astro modules
#
use Astro::VO::VOEvent;

my ($log, $process, $ua, $config, $running);

# ==========================================================================
# U S E R   A U T H E N T I C A T I O N
# ==========================================================================

sub new {
  my ( $class, $user, $passwd ) = @_;
  
  my $self = bless {}, $class;
  $log = eSTAR::Logging::get_reference();
  $process = eSTAR::Process::get_reference();
  $ua = eSTAR::UserAgent::get_reference();
  $config = eSTAR::Config::get_reference();
  $running = eSTAR::Broker::Running::get_reference();
  
  if( $user and $passwd ) {
    return undef unless $self->set_user( user => $user, password => $passwd );
  }
  
  $log->thread2( "Handler Thread", 
  "Created new eSTAR::Broker::SOAP::Handler object (\$tid = ".threads->tid().")");
        
  return $self;
}

# intialise and load specific user information into the main object
sub set_user {
   my ($self, %args ) = @_;
   
   $self->{_user} = new eSTAR::SOAP::User();
   unless ( ref($self) and $args{user} and 
            $self->{_user}->get_user($args{user})) {
            
      # user isn't know, return error string      
      undef $self->{_user};
      
      $log->warn("SOAP Request: Could not load data for $args{user}");
      return "Could not load data for $args{user}";
   }
   
   # user data is loaded beforehand, so that the password is available
   # for testing. If the validation fails, user object is destroyed
   # before the error is sent, so that the called does not accidentially
   # get the user data.
   if( $args{password} ) {

      unless( $args{password} eq $self->{_user}->passwd()) {
      
         undef $self->{_user};
      
         $log->warn("SOAP Request: Bad password for $args{user}");
         return "Bad password for $args{user}";
      }
      
   } elsif( $args{cookie} ) {

      unless( $args{cookie} eq 
         eSTAR::Util::make_cookie($args{user}, $self->{_user}->{passwd}) ) {
              
         undef $self->{_user};

         $log->warn(
            "SOAP Request: Authentication token for $args{user} invalid");
         return "Authentication token for $args{user} invalid";
      }
      
   } else {
   
      undef $self->{_user};

      $log->warn(
          "SOAP Request: No authentication present for $args{user}");
      return "No authentication present for $args{user}";
   
   } 
   
   $log->print( "SOAP Request: from $args{user} on ". ctime() );
   return $self;             
}

# ==========================================================================
# O P T I O N S  H A N D L E R S 
# ==========================================================================

# option handling
sub get_option {
   my $self = shift;

   $log->debug("Called get_option() from \$tid = ".threads->tid());
   $config->reread();
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
   
   # grab the arguement telling us what we're looking for...
   my $option = shift;

   my $value = $config->get_option( $option );
   if ( $value == ESTAR__ERROR ) {
      $log->error("Error: Unable to get value from configuration file" );
      die SOAP::Fault
     ->faultcode("Client.FileError")
     ->faultstring("Client Error: Unable to get value from configuration file");          
   }

   $log->debug("Returned RESULT message");
   return SOAP::Data->name('return', $value )->type('xsd:string');
} 

sub set_option {
   my $self = shift;

   $log->debug("Called set_option() from \$tid = ".threads->tid());   
   $config->reread();
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
   
   my $option = shift;
   my $value = shift;


   $log->debug("Setting $option = $value");
   my $status = $config->set_option( $option, $value );
   if ( $status == ESTAR__ERROR ) {
      $log->error("Error: Unable to set value in configuration file" );
      die SOAP::Fault
      ->faultcode("Client.FileError")
      ->faultstring("Client Error: Unable to set value in configuration file");          
   }   
   
   $log->debug("Writing out options file...");
   my $status = $config->write_option();
   if ( $status == ESTAR__ERROR ) {
      $log->error("Error: Unable to write out to configuration file" );
      die SOAP::Fault
      ->faultcode("Client.FileError")
      ->faultstring("Client Error: Unable to write out to configuration file");          
   }

   $log->debug("Returned STATUS message" );
   return SOAP::Data->name('return', ESTAR__OK )->type('xsd:integer');

} 

# ==========================================================================
# D A T A  H A N D L E R S 
# ==========================================================================

# test function
sub ping {
   my $self = shift;

   $log->debug("Called ping() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
     
   $log->debug("Returned ACK message");
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
} 

# test function
sub echo {
   my $self = shift;
   my @args = @_;

   $log->debug("Called echo() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
     
   $log->debug("Returned ECHO message");
   return SOAP::Data->name('return', "ECHO @args")->type('xsd:string');
} 

# a kludge
sub kill {
   my $self = shift;

   $log->debug("Called kill() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data"
   }
   
   $log->print("Spawning thread to kill agent...");
   my $kill_thread = threads->create( sub { 
                                       sleep 5; 
                                       main::kill_agent( ESTAR__FATAL ); } );
   $kill_thread->detach();
     
   $log->debug("Returned ACK message");
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
}


# handle an incoming VOEvent documents
sub handle_voevent {
   my $self = shift;
   my $name = shift;
   my $voevent = shift;

   #print Dumper( $rtml );
   $log->debug("Called handle_voevent() from \$tid = ".threads->tid());
   $config->reread();
   
   # check we have a valid user object            
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data");
      return "The object is missing user data";
   }
   
   # Message Validation
   # ------------------
   
   # validate the incoming message
   my $message;
   eval { $message = new Astro::VO::VOEvent( XML => $voevent ) };
   
   if ( $@ ) {
       my $error = "$@";
       
       $log->error( "Error: Problem parsing the VOEvent document" );
       $log->error( "VOEvent Document:\n$voevent" );
       $log->error( "Returned SOAP FAULT message" );
       die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $error\nVOEvent Document:\n$voevent");
   }      
   my $id = $event->id();
   

   # HANDLE VOEVENT MESSAGE --------------------------------------------
   #
   # At this stage we have a valid alert message
   
   # Push message onto running hash via the object we've set up for that
   # purpose...
   eval { $running->add_message( $id, $message ); };
   if ( $@ ) {
      my $error = "$@";
      chomp( $error );
      $log->error( "Error: Can't add message $id to new message hash");
      $log->error( "Error: $error" );
       $log->error( "Returned SOAP FAULT message" );
       die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $error\nVOEvent Document:\n$voevent");      
   }  
   	  
   # log the event message
   my $file;
   eval { $file = eSTAR::Broker::Util::store_voevent( $name, $message ); };
   if ( $@  ) {
     my $error = "$@";
      $log->error( "Error: Can't store message $id on disk");
      $log->error( "Error: $error" );
       $log->error( "Returned SOAP FAULT message" );
       die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $error\nVOEvent Document:\n$voevent");      
   } 
   
   unless ( defined $file ) {
      $log->warn( "Warning: The message has not been serialised..." );
   }
       
   
   # Upload the event message to estar.org.uk
   # ----------------------------------------
   $log->debug("Opening FTP connection to lion.drogon.net...");  
   $log->debug("Logging into estar account...");  
   my $ftp = Net::FTP->new( "lion.drogon.net", Debug => 0 );
   $ftp->login( "estar", "tibileot" );
   
   my $idpath = $id; 
   $idpath =~ s/#/\//;     
   my @path = split( "/", $idpath );
   if ( $path[0] eq "ivo:" ) {
      splice @path, 0 , 1;
   }
   if ( $path[0] eq "" ) {
      splice @path, 0 , 1;
   }
   my $path = "www.estar.org.uk/docs/voevent/$name";  
   foreach my $i ( 0 ... $#path - 1 ) {
      if ( $path[$i] eq "" ) {
   	next;
      }
      $path = $path . "/$path[$i]";	   
   }
   $log->debug("Changing directory to $path");
   unless ( $ftp->cwd( $path ) ) {
      $log->warn( "Warning: Recursively creating directories..." );
      $log->warn( "Warning: Path is $path");
      $ftp->mkdir( $path, 1 );
      $ftp->cwd( $path );
      $log->debug("Changing directory to $path");
   }
   $log->debug("Uploading $file");
   $ftp->put( $file, "$path[$#path].xml" );
   $ftp->quit();    
   $log->debug("Closing FTP connection"); 

   # Writing to alert.log file
   my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
   my $alert = File::Spec->catfile( $state_dir, $name, "alert.log" );
   
   $log->debug("Opening alert log file: $alert");  
   	 
   # write the observation object to disk.
   # -------------------------------------
   
   unless ( open ( ALERT, "+>>$alert" )) {
      my $error = "Warning: Can not write to "  . $state_dir; 
      $log->error( $error );
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);   
   } else {
      unless ( flock( ALERT, LOCK_EX ) ) {
   	my $error = "Warning: unable to acquire exclusive lock: $!";
   	$log->error( $error );
   	throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
      } else {
   	$log->debug("Acquiring exclusive lock...");
      }
   }	    
   
   $log->debug("Writing file path to $alert");
   print ALERT "$file\n";
   
   # close ALERT log file
   $log->debug("Closing alert.log file...");
   close(ALERT);  

   # GENERATE RSS FEED -------------------------------------------------
   
   
   # Reading from alert.log file
   # ---------------------------     
   $log->debug("Opening alert log file: $alert");  
    
   # write the observation object to disk.
   unless ( open ( LOG, "$alert" )) {
      my $error = "Warning: Can not read from "  . $state_dir; 
      $log->error( $error );
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);   
   } else {
      unless ( flock( LOG, LOCK_EX ) ) {
   	my $error = "Warning: unable to acquire exclusive lock: $!";
   	$log->error( $error );
   	throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
      } else {
   	$log->debug("Acquiring exclusive lock...");
      }
   }	    
   
   $log->debug("Reading from $alert");
   my @files;
   {
      local $/ = "\n";  # I shouldn't have to do this?
      @files = <LOG>;
   }   
   # use Data::Dumper; print "\@files = " . Dumper( @files );
   
   $log->debug("Closing alert.log file...");
   close(LOG);
   	
   # Writing to broker.rdf
   # ---------------------
   my $state_dir = File::Spec->catdir( $config->get_state_dir() );  
   my $rss = File::Spec->catfile( $state_dir, $name, "$name.rdf" );
      
   $log->debug("Creating RSS file: $rss");  
   	
   # write the observation object to disk.
   unless ( open ( RSS, ">$rss" )) {
      my $error = "Warning: Can not write to "  . $state_dir; 
      $log->error( $error );
      throw eSTAR::Error::FatalError($error, ESTAR__FATAL);   
   } else {
      unless ( flock( RSS, LOCK_EX ) ) {
   	my $error = "Warning: unable to acquire exclusive lock: $!";
   	$log->error( $error );
   	throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
      } else {
   	$log->debug("Acquiring exclusive lock...");
      }
   }		      
   
   $log->print( "Creating RSS feed..." );     
   
   my $timestamp = eSTAR::Broker::Util::time_iso( );
   my $rfc822 = eSTAR::Broker::Util::time_rfc822( );
   
   my $feed = new XML::RSS( version => "2.0" );
   $feed->channel(
      title	   => "$name Event Feed",
      link	   => "http://www.estar.org.uk",
      description  => 
        'This is an RSS2.0 feed from '.$name.' of VOEvent notices brokered '.
        'through the eSTAR agent network.Contact Alasdair Allan '.
        '<aa@estar.org.uk> for information about this and other eSTAR feeds. ' .
        'More information about the eSTAR Project can be found on our '.
        '<a href="http://www.estar.org.uk/">website</a>.',
      pubDate	     => $rfc822,
      lastBuildDate  => $rfc822,
      language       => 'en-us' );

   $feed->image(
   	   title       => 'estar.org.uk',
   	   url         => 'http://www.estar.org.uk/favicon.png',
   	   link        => 'http://www.estar.org.uk/',
   	   width       => 16,
   	   height      => 16,
   	   description => 'eSTAR' );
    
   my $num_of_files = $#files;
   my $start = 0;
   if ( $num_of_files >= 20 ) {
      $start = $num_of_files - 20;
   }	 
 
   my @not_present;
   for ( my $i = $num_of_files; $i >= $start; $i-- ) {
      $log->debug( "Reading $i of $num_of_files entries" );
      my $data;
      {
   	 open( DATA_FILE, "$files[$i]" );
   	 local ( $/ );
   	 $data = <DATA_FILE>;
   	 close( DATA_FILE );

      }  
      
      #  use Data::Dumper; print "\@data = " . Dumper( $data );
      
      #$log->debug( "Opening: $files[$i]" );
      $log->debug( "Determing ID of message..." );
      my $object;
      eval { $object = new Astro::VO::VOEvent( XML => $data ); };
      if ( $@ ) {
   	 my $error = "$@";
   	 chomp( $error );
   	 $log->error( "Error: $error" );
   	 $log->error( "Error: Can't open ". $files[$i] );
   	 $log->warn( "Warning: discarding message $i of $num_of_files" );
   	 push @not_present, $i;
   	 next;
      } 
      my $id;
      eval { $id = $object->id( ); };
      if ( $@ ) {
   	 my $error = "$@";
   	 chomp( $error );
   	 $log->error( "Error: $error" );
   	 $log->error( "\$data = " . $data );
   	 $log->warn( "Warning: discarding message $i of $num_of_files" );
   	 next;
      } 
      $log->debug( "ID: $id" );
  
      # grab <What>
      my %what = $object->what();
      my $packet_type = $what{Param}->{PACKET_TYPE}->{value};
 
      my $packet_timestamp = $object->time();
      my $packet_rfc822;
      eval { $packet_rfc822 = 
        	 eSTAR::Broker::Util::iso_to_rfc822( $packet_timestamp ); };
      if ( $@ ) {
         $log->warn( 
            "Warning: Unable to parse $packet_timestamp as valid ISO8601");
      }   
   	    
      # grab role
      my $packet_role = $object->role();
             
      # build url
      my $idpath = $id;
      $idpath =~ s/#/\//;
      my @path = split( "/", $idpath );
      if ( $path[0] eq "ivo:" ) {
   	 splice @path, 0 , 1;
      }
      if ( $path[0] eq "" ) {
   	 splice @path, 0 , 1;
      }
      my $url = "http://www.estar.org.uk/voevent/$name";
      foreach my $i ( 0 ... $#path ) {
   	 $url = $url . "/$path[$i]"; 
      }
      $url = $url . ".xml";
   
      my $description;
      if ( defined $packet_type && lc($id) =~ "gcn" ) {
        $description = "GCN PACKET_TYPE = $packet_type (via $name)<br>\n" .
   		       "Time stamp at $name was $packet_timestamp<br>\n".
        	       "Packet role was '".$packet_role."'";
      } else {
        $description = "Received packet (via $name) at $packet_timestamp<br>\n".
        	       "Packet role was '".$packet_role."'";
      } 	       
   
      $log->print( "Creating RSS Feed Entry..." );
      if ( defined $packet_rfc822 ) {
         $feed->add_item(
   	 title       => "$id",
   	 description => "$description",
   	 link	     => "$url",
         pubDate     => "$packet_rfc822",
   	 enclosure   => { 
   	   url    => $url, 
   	   type   => "application/xml+voevent",
   	   length => length($data) } );
      } else {
         $feed->add_item(
   	 title       => "$id",
   	 description => "$description",
   	 link	     => "$url",
   	 enclosure   => { 
   	   url    => $url, 
   	   type   => "application/xml+voevent",
   	   length => length($data) } );
      }     
   }
   $log->debug( "Creating XML representation of feed..." );
   my $xml = $feed->as_string();

   $log->debug( "Writing feed to $rss" );
   print RSS $xml;
     
   # close ALERT log file
   $log->debug("Closing $name.rdf file...");
   close(RSS);    
   
   $log->debug("Opening FTP connection to lion.drogon.net...");  
   my $ftp2 = Net::FTP->new( "lion.drogon.net", Debug => 0 );
   $log->debug("Logging into estar account...");  
   $ftp2->login( "estar", "tibileot" );
   $ftp2->cwd( "www.estar.org.uk/docs/voevent/$name" );
   $log->debug("Transfering RSS file...");  
   $ftp2->put( $rss, "$name.rdf" );
   $ftp2->quit();     
   $log->debug("Closed FTP connection");  

   # Clean up the alert.log file
   # ---------------------------
   if ( defined $not_present[0] ) {
     $log->warn( "Cleaning up $name alert.log file" );
  
     $log->warn( "Warning: Opening $alert" );
     unless ( open ( ALERT, "+>$alert" )) {
   	my $error = "Error: Can not write to "  . $state_dir; 
   	$log->error( $error );
   	throw eSTAR::Error::FatalError($error, ESTAR__FATAL);	
     } else {
   	unless ( flock( ALERT, LOCK_EX ) ) {
   	  my $error = "Error: unable to acquire exclusive lock: $!";
   	  $log->error( $error );
   	  throw eSTAR::Error::FatalError($error, ESTAR__FATAL);
       } else {
   	 $log->warn("Warning: Acquiring exclusive lock...");
       }
     }        
   
    $log->warn( "Warning: Writing to $alert" );
    foreach my $k ( 0 ... $#files ) {
   	
   	my $flag = 0;
   	foreach my $l ( 0 ... $#not_present ) {
   	   $flag = 1 if $k == $not_present[$l];
   	}
   	
   	unless ( $flag ) {   
   	   $log->warn("$files[$k] (line $k of $#files)");
   	   print ALERT "$files[$k]";
   	} else {
   	   $log->error("$files[$k] (DELETED)");
   	}	  
     }
     
     # close ALERT log file
     $log->warn("Warning: Closing alert.log file...");
     close(ALERT);	 
     
   } # end clenaup of alert.log file
      
   
   $log->debug( "Returning 'ACK' message" );
   return SOAP::Data->name('return', 'ACK')->type('xsd:string');
}

              
1;                                
                  
                  
                  
                  
                  
                  
