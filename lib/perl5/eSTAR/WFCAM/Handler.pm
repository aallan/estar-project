package eSTAR::WFCAM::Handler;

# Basic handler class for SOAP requests for the WFCAM Agent. It also
# acts as a container class for eSTAR::SOAP::User class which handles
# authentication.

use lib $ENV{"ESTAR_PERL5LIB"};     

use strict;
use subs qw( new ping echo get_option set_option 
             populate_db query_db handle_objects );

#
# Threading code (ithreads)
# 
use threads;
use threads::shared;

#
# General modules
#
use Config::Simple;
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use Time::localtime;
use Sys::Hostname;
use Net::Domain qw(hostname hostdomain);
use Config::Simple;
use Config::User;
use Data::Dumper;
use Fcntl qw(:DEFAULT :flock);
use Compress::Zlib;

# 
# eSTAR modules
#
use eSTAR::SOAP::User;
use eSTAR::Logging;
use eSTAR::Constants qw/:all/;
use eSTAR::Util;
use eSTAR::Process;
use eSTAR::Mail;
use eSTAR::Config;
use eSTAR::Database::Manip;
use eSTAR::Database::DBbackend;

#
# Astro modules
#
use Astro::Catalog;
use Astro::Catalog::Item;
use Astro::Catalog::Star;

my ($log, $process, $ua, $config);

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
    
  if( $user and $passwd ) {
    return undef unless $self->set_user( user => $user, password => $passwd );
  }
  
  $log->thread2( "Handler Thread", 
    "Created new eSTAR::WFCAM::Handler object (\$tid = ".threads->tid().")");
        
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
# C A L L B A C K S  F R O M   H A N D L E R S 
# ==========================================================================


sub do_datamining {
  croak ( "eSTAR::WFCAM::Handler::do_datamining() called without arguements" )
     unless defined @_;

  my $catalog = shift;   
     
  my $thread_name = "do_datamining()";
  $log->thread($thread_name, "eSTAR::WFCAM::Handler::do_datamining()..." );
  $log->thread($thread_name, "Starting client (\$tid = ".threads->tid().")");  
     
  $log->debug( "Calling eSTAR::Util::chill( \$catalog )");
  $catalog->reset_list(); # otherwise we breake the serialisation
  my $chilled = eSTAR::Util::chill( $catalog );
  
  $log->debug( "Compressing \$catalog");
  my $compressed = Compress::Zlib::memGzip( $chilled );
  
  $log->thread( $thread_name, "Connecting to Data Mining Service..." );
  
  my $endpoint = "http://" . $config->get_option( "miner.host") . ":" .
              $config->get_option( "miner.port");
  my $uri = new URI($endpoint);
  $log->debug("Web service endpoint $endpoint" );
  
  # create a user/passwd cookie
  $log->debug("Creating cookie..." );
  my $cookie = eSTAR::Util::make_cookie( "agent", "InterProcessCommunication" );
  
  $log->debug("Dropping cookie in jar..." );
  my $cookie_jar = HTTP::Cookies->new();
  $cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

  # create SOAP connection
  my $soap = new SOAP::Lite();
  
  my $urn = "urn:/" . $config->get_option( "miner.urn" );
  $log->debug( "URN of endpoint service is $urn");
  
  $soap->uri($urn); 
  $soap->proxy($endpoint, cookie_jar => $cookie_jar);
    
  #use Data::Dumper;
  #print Dumper( $chilled[0] );  
    
  # report
  $log->thread( $thread_name, "Calling handle_objects() in remote service");
    
  # grab result 
  my $result;
  my $host = $config->get_option( "server.host" );
  my $port = $config->get_option( "server.port" );
  eval { $result = $soap->handle_objects( $host, $port, 
                             SOAP::Data->type(base64 => $compressed ) ); };
  if ( $@ ) {
    $log->warn( "Warning: Could not connect to $endpoint");
    $log->warn( "Warning: $@" );
      
  }  
  
  $log->debug( "Transport status: " . $soap->transport()->status() );
  unless ( defined $result ) {
    $log->error("Error: No result object is present..." );
    $log->error("Error: Returning ESTAR__FAULT to main thread" );
    return ESTAR__FAULT;
  }
    
  unless ($result->fault() ) {
    if ( $result->result() eq "OK" ) {
       $log->debug( "Recieved an ACK message from data mining service");
    } else {
       $log->warn( "Warning: Recieved status ".$result->result() .
                   " from data mining service");
    }   
  } else {
    $log->warn("Warning: recieved fault code (" . $result->faultcode() .")" );
    $log->warn("Warning: " . $result->faultstring() );
    $log->thread( $thread_name, "Returning ESTAR__FAULT to main thread");
    return ESTAR__FAULT;
  }  

  $log->thread( $thread_name, "Returning ESTAR__OK to main thread");
  return ESTAR__OK;       
     
}


# ==========================================================================
# T E S T  H A N D L E R S 
# ==========================================================================

# test function
sub ping {
   my $self = shift;

   $log->debug("Called ping() from \$tid = ".threads->tid());
   
   # not callable as a static method, so must have a value
   # user object stored within             
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
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
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
     
   $log->debug("Returned ECHO message");
   return SOAP::Data->name('return', "ECHO @args")->type('xsd:string');
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

sub populate_db {
   my $self = shift;
   my @args = @_;
   
   $log->debug("Called populate_db() from \$tid = ".threads->tid());
   $config->reread();
   
   # CHECK FOR USER DATA
   # ===================
   
   # not callable as a static method, so must have a value user object 
   # stored within the class otherwise we'll return a SOAP Error            
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }
   
   # CHECK CATALOGUES
   # ================

   my $num_cat = scalar( @args );
   $log->debug("Recieved " . $num_cat . " catalogues...");
   unless ( $num_cat => 6 ) {
      my $error = "populate_db() called without too few ($num_cat<6) catalogues";
      $log->error("Error: $error");
      $log->warn("Warning: Returned SOAP Error message");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $error");	    
   }
 
   foreach my $i ( 0 ... $#args ) {
      $log->debug( "Uncompressing catalogue[$i]...");
      $args[$i] = Compress::Zlib::memGunzip( $args[$i] );
   }
   	    
   $log->debug( "Calling eSTAR::Util::reheat( \$new_objects )");
   my $new_objects = eSTAR::Util::reheat( $args[0] );
   $log->debug( "Calling eSTAR::Util::reheat( \$var_objects )");
   my $var_objects = eSTAR::Util::reheat( $args[1] );
   
   my @catalogs;
   $log->debug( "Calling eSTAR::Util::reheat( \@catalogues )");
   foreach my $i ( 2 ... $#args) {
      push @catalogs, eSTAR::Util::reheat( $args[$i] );
   }

  use Data::Dumper;
  print "DIRECTLY AFTER RECIEVEING VIA WEBSERVICE\n";  
  print Dumper( $catalogs[0]->starbyindex(0) );
  
   # try and catch parsing errors here...
   if( $@ ) {
      $log->error("Error: $@");
      $log->warn("Warning: Returned SOAP Error message");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $@")
   } 
   
   # sanity check the passed values
   $log->debug("Doing a sanity check on the integrity of the catalogues");
   my $check = 1;
   foreach my $catalog ( @catalogs ) {
      $check = undef unless UNIVERSAL::isa( $catalog, "Astro::Catalog" );
   }      
   unless ( UNIVERSAL::isa( $new_objects, "Astro::Catalog" ) &&
            UNIVERSAL::isa( $var_objects, "Astro::Catalog" ) && $check ) {
      my $error = "The catalogues were not successfully deserialised";
      $log->error("Error: $error");
      $log->warn("Warning: Returned SOAP Error message");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $error");	    
   } else {
      $log->debug( "All the references appear to be Astro::Catalog objects");
      
      #if( ESTAR__DEBUG ) {
      
        $log->warn("Warning: Doing paranoia checks, this will take time...");
	
	# this is me going off the deep end
	unless ( "@Astro::Catalog::Star::ISA" eq "Astro::Catalog::Item" ) {
	
	   $log->warn("Warning: An Astro::Catalog::Star doesn't seem to be an" .
	   " Astro::Catalog::Item. This shouldn't happen!" )
        } else {
	   $log->debug( 'An Astro::Catalog::Star->isa("Astro::Catalog::Item")');
	}
	   
        # but this is just paranoia
        my $counter = 0;
        foreach my $star ( $new_objects->allstars() ) {
          $log->warn("Warning: Problem deserialising star $counter from ".
	   " \$new_objects") unless UNIVERSAL::isa($star, "Astro::Catalog::Star");
	  $counter++;
        }
        foreach my $star ( $var_objects->allstars() ) {
          $log->warn("Warning: Problem deserialising star $counter from ".
	   " \$var_objects") unless UNIVERSAL::isa($star, "Astro::Catalog::Star");
	  $counter++;
        }     
        foreach my $catalog ( @catalogs ) {
           $counter = 0;
	   my $cat = 1;
           foreach my $star ( $catalog->allstars() ) {
             $log->warn("Warning: Problem deserialising star $counter from ".
	      " \$catalog number $cat") 
	      unless UNIVERSAL::isa($star, "Astro::Catalog::Star");
	     $counter++;
	     $cat++;
           } 
        }
	
     # }	       
   }


  # POPULATE DB
  # ===========

#$log->warn("WARNING: NOT CONTACTING DATABASE");
  $log->print("Attempting to contact database...");

  # Set up DB object and add catalogues to database.  
  $log->debug( "Creating a DB backend reference");
  my $db_ref;
  eval { $db_ref = new eSTAR::Database::DBbackend(); }; 
  if ( $@ ) {
     my $error = "$@";
     $log->error( "Error: $error" );
     $log->error("Returned ESTAR__FAULT message");
     return ESTAR__FAULT;
  }  
    
  $log->debug( "Creating a manipulation object...");
  my $db;
  eval { $db = new eSTAR::Database::Manip( DB => $db_ref ); };
  if ( $@ ) {
     my $error = "$@";
     $log->error( "Error: $error" );
     $log->error("Returned ESTAR__FAULT message");
     return ESTAR__FAULT;
  }   
  
  foreach my $cat ( @catalogs ) {
    $log->debug( "Adding catalogue to database...");
    
    #use Data::Dumper; print Dumper( $cat );
    eval { $db->add_catalog( $cat ); };
    if ( $@ ) {
        my $error = "$@";
        $log->error( "Error: $error" );
        $log->error("Returned ESTAR__FAULT message");
        return ESTAR__FAULT;
    }      
    $log->debug( "Successfully added catalogue to database..." );
  }

  foreach my $var_item ( $var_objects->allstars ) {
    $log->debug( "Updating item with ID " . $var_item->id . 
		 " as eSTAR_variable" );
    eval { $db->update_flags( $var_item, [ 'eSTAR_variable' ] ); };
    if ( $@ ) {
        my $error = "$@";
        $log->error( "Error: $error" );
        $log->error("Returned ESTAR__FAULT message");
        return ESTAR__FAULT;
    } 
  }
  foreach my $new_item ( $new_objects->allstars ) {
    $log->debug( "Updating item with ID " . $new_item->id . 
		 " as eSTAR_new" );
    eval { $db->update_flags( $new_item, [ 'eSTAR_new' ] ); };
    if ( $@ ) {
        my $error = "$@";
        $log->error( "Error: $error" );
        $log->error("Returned ESTAR__FAULT message");
        return ESTAR__FAULT;
    } 
  }

  $log->print("Objects injested into database...");

  # CALL DATA MINING PROCESS
  # ======================== 
     
  $log->print( "Creating thread to data mine candidate variables..." );
  my $dispatch = threads->create( \&do_datamining, $var_objects );
  				  
  unless ( defined $dispatch ) {
     $log->error( "Error: Could not spawn a thread to talk to the DB" );
     $log->error( "Error: Returning ESTAR__FATAL to main loop..." );
     return ESTAR__FATAL;  
  }				  
  $log->debug( "Detaching thread...");
  $dispatch->detach();
   
  # RETURN OK MESSAGE TO CLIENT
  # ===========================
  
  # return an OK message to the client
  $log->debug("Returned OK message");
  return SOAP::Data->name('return', "OK")->type('xsd:string');
      
}
  

sub query_db {
   my $self = shift;
   my @args = @_;
   
   $log->debug("Called query_db() from \$tid = ".threads->tid());
   $config->reread();
  
   # CHECK FOR USER DATA
   # ===================
   
   # not callable as a static method, so must have a value user object 
   # stored within the class otherwise we'll return a SOAP Error            
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }  

 
   # RETURN OK MESSAGE TO CLIENT
   # ===========================
   
   # return an OK message to the client
   $log->debug("Returned OK message");
   return SOAP::Data->name('return', "OK")->type('xsd:string');

}  

sub handle_objects {
   my $self = shift;
   my $compressed = shift;  
      
   $log->debug("Called handle_objects() from \$tid = ".threads->tid());
   $config->reread();
  
   # CHECK FOR USER DATA
   # ===================
   
   # not callable as a static method, so must have a value user object 
   # stored within the class otherwise we'll return a SOAP Error            
   unless ( my $user = $self->{_user}) {
      $log->warn("SOAP Request: The object is missing user data.");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: The object is missing user data.")
   }  
   
   $log->debug( "Uncompressing catalogue...");
   my $string = Compress::Zlib::memGunzip( $compressed );
   	    
   $log->debug( "Calling eSTAR::Util::reheat( \$catalog )");
   my $catalog = eSTAR::Util::reheat( $string );

   # try and catch parsing errors here...
   if( $@ ) {
      $log->error("Error: $@");
      $log->warn("Warning: Returned SOAP Error message");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $@")
   } 
   
   # sanity check the passed values
   $log->debug("Doing a sanity check on the integrity of the catalogues");
   unless ( UNIVERSAL::isa( $catalog, "Astro::Catalog" ) ) {
      my $error = "Passed catalogue does not parse correctly";
      $log->error("Error: $error");
      $log->warn("Warning: Returned SOAP Error message");
      die SOAP::Fault
         ->faultcode("Client.DataError")
         ->faultstring("Client Error: $error")   
 
   } else {
      $log->debug( "Reference appears to be Astro::Catalog object");
   }  
 
   #print Dumper ( $catalog );
   $log->print("Attempting to contact database...");

   # Set up DB object and add catalogues to database.
   $log->debug( "Creating a DB backend reference");
   my $db_ref;
   eval { $db_ref = new eSTAR::Database::DBbackend(); }; 
   if ( $@ ) {
      my $error = "$@";
      $log->error( "Error: $error" );
      $log->error("Returned ESTAR__FAULT message");
      return ESTAR__FAULT;
   }  
    
   $log->debug( "Creating a manipulation object...");
   my $db;
   eval { $db = new eSTAR::Database::Manip( DB => $db_ref ); };
   if ( $@ ) {
      my $error = "$@";
      $log->error( "Error: $error" );
      $log->error("Returned ESTAR__FAULT message");
      return ESTAR__FAULT;
   }   

   $log->debug("Updating the DB with SIMBAD results...");
   foreach my $item ( $catalog->allstars ) {
     $log->debug( "Updating item with ID " . $item->id . 
 		  " as SIMBAD_variable" );
     eval { $db->update_flags( $item, [ 'SIMBAD_variable' ] ); };
     if ( $@ ) {
         my $error = "$@";
         $log->error( "Error: $error" );
         $log->error("Returned ESTAR__FAULT message");
         return ESTAR__FAULT;
     }     
   }   
 
   # RETURN OK MESSAGE TO CLIENT
   # ===========================
   
   # return an OK message to the client
   $log->debug("Returned OK message");
   return SOAP::Data->name('return', "OK")->type('xsd:string');

}
   
1;                                
                  
                  
                  
                  
                  
                  
