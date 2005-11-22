package eSTAR::Config;


use strict;
#use warnings;

require Exporter;
use Config::Simple;
use Fcntl qw(:DEFAULT :flock);
use Data::Dumper;

#use eSTAR::Logging;
#use eSTAR::Process;
use eSTAR::Constants qw/:all/;

use vars qw/$VERSION @EXPORT @ISA/;

@ISA = qw/Exporter/;
@EXPORT = qw/ get_option set_option write_option get_nodes get_node_names
              get_state set_state write_state make_directories
              get_data_dir get_state_dir get_tmp_dir
              get_useragents get_useragent_names /;

'$Revision: 1.17 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

my $SINGLETON;

my ($log, $process);
sub new {
   return $SINGLETON if defined $SINGLETON;

   my $proto = shift;
   my $class = ref($proto) || $proto;   
   $SINGLETON = bless { CONFIG      => undef,
                        CONFIG_FILE => undef,
                        STATE       => undef,
                        STATE_FILE  => undef }, $class;

   $log = eSTAR::Logging::get_reference();
   $process = eSTAR::Process::get_reference();
   
   $SINGLETON->{CONFIG_FILE} = 
         File::Spec->catfile( Config::User->Home(), '.estar', 
                              $process->get_process(), 'options.dat' ); 
   $SINGLETON->{CONFIG} = create_ini_file( $SINGLETON->{CONFIG_FILE} );

   $SINGLETON->{STATE_FILE} = 
         File::Spec->catfile( Config::User->Home(), '.estar', 
                              $process->get_process(), 'state.dat' ); 
   $SINGLETON->{STATE} = create_ini_file( $SINGLETON->{STATE_FILE} );
 
   return $SINGLETON;
}

sub get_reference {
  return $SINGLETON if defined $SINGLETON;
  return undef;
}


sub reread {
   my $self = shift;
   
   my $log = eSTAR::Logging::get_reference();
   
   $log->debug( "Forced read of " . $self->{CONFIG_FILE} );
   if ( open ( CONFIG, $self->{CONFIG_FILE} ) ) {
      close( CONFIG );   
         
      eval {
         $self->{CONFIG} = undef;
         $self->{CONFIG} = create_ini_file( $self->{CONFIG_FILE} );
      };
      if ( $@ ) {
         my $warning = "$@";
         chomp ( $warning );
         $log->warn("Warning: " . $warning );
      } 
        
   } else {
      $log->warn("Warning: " . $self->{CONFIG_FILE}. " does not exist.");
   }

   $log->debug( "Forced read of " . $self->{STATE_FILE} );
   if ( open ( STATE, $self->{STATE_FILE} ) ) {
      close( STATE );

      eval {
         $self->{STATE} = undef;
         $self->{STATE} = create_ini_file( $self->{STATE_FILE} );
      
      };
      if ( $@ ) {
         my $warning = "$@";
         chomp ( $warning );
         $log->warn("Warning: " . $warning );
      }  
       
   } else {
      $log->warn("Warning: " .$self->{STATE_FILE} . " does not exist.");
   }   
 
} 
   
# create a configuration file
sub create_ini_file {
   my $file = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();
   
   # if it exists read the current contents in...
   my $CONFIG;
   if ( open ( FILE, "<$file" ) ) {
      close( FILE );
      
      $log->debug("eSTAR::Config - Attempting to read $file");
      $CONFIG = new Config::Simple( mode => O_RDWR );
      $CONFIG->syntax( 'ini' );
      $CONFIG->read( $file );
      
    #  $log->debug( Dumper( $CONFIG ) );
   } else {
      $log->warn("Warning: eSTAR::Config is creating new config file $file");
      $CONFIG = new Config::Simple( syntax   => 'ini', 
                                    mode     => O_RDWR|O_CREAT );
      
      $CONFIG->syntax( 'ini' );
      $CONFIG->param( "file.name", $file );
      $CONFIG->save( $file );
   }
   
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "Error: Problems creating Config::Simple() object";
      $log->error( $error );
      $error = "Error: Config::Simple reported '" 
               . $Config::Simple::errstr . "'";
      $log->error( $error );
      
      return undef;      
   }
    
   unless ( defined $CONFIG->param( "file.name" ) ) {
       # can't read/write to options file, bail out
      my $error = 
        "Error: Problems with sanity check of Config::Simple() object";
      $log->error( $error );
      $error = "Error: Config::Simple reported '" 
               . $Config::Simple::errstr . "'";
      $log->error( $error );
      
      $log->error( Dumper( $CONFIG ) );
      return undef;    
   }
    
   return $CONFIG; 
}

# grab an option from the $CONFIG file
sub get_option {
   my $self = shift;
   my $option = shift;
   #my ( $section, $parameter ) = split( ".", $option );

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{CONFIG_FILE};
 
   $log->debug("Looking up $option in $config_file");
   
   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );     
      return undef;      
   } 
   
   #unless ( $CONFIG->param($option ) ) {
   #   $log->error("Error: Can not get $option from options.dat file");
   #   return ESTAR__ERROR;   
   #}
   
   if ( defined $CONFIG->param( $option ) ) {
      $log->debug( $option . " = " .  $CONFIG->param( $option ) ); 
   } else {
      $log->warn( "Warning: $option is currently undefined" );
      
   }
   my $value = $CONFIG->param( $option );
   #$CONFIG->close();
   #undef $CONFIG;
   
   return $value;
} 

# set an option in the $CONFIG file
sub set_option {
   my $self = shift;
   my $option = shift;
   my $value = shift;
   #my ( $section, $parameter ) = split( ".", $option );

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{CONFIG_FILE};

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not write to $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   $CONFIG->param( $option, $value );
   my $status = $CONFIG->save( $config_file );
   #$CONFIG->close();
   #undef $CONFIG;
   
   return ESTAR__OK;

} 

sub write_option {
   my $self = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{CONFIG_FILE};

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not write to $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   my $status = $CONFIG->save( $config_file );
   #$CONFIG->close();
   #undef $CONFIG;
   
   return $status;
}   

# grab an option from the $STATE file
sub get_state {
   my $self = shift;
   my $option = shift;
   #my ( $section, $parameter ) = split( ".", $option );

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{STATE_FILE}; 

   $log->debug("Looking up $option in $config_file");
   my $STATE = $self->{STATE};
   unless ( defined $STATE ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 
   
    
   #unless ( $STATE->param( $option ) ) {
   #   $log->error("Error: Can not get $option from state.dat file");
   #   return ESTAR__ERROR;   
   #}
   
   if ( defined $STATE->param( $option ) ) {
      $log->debug( $option . " = " .  $STATE->param( $option ) ); 
   } else {
      $log->warn( "Warning: $option is currently undefined" );
   }       
   my $value = $STATE->param( $option );
   #$STATE->close();
   #undef $STATE;
   
   return $value;
} 

# set an option in the $STATE file
sub set_state {
   my $self = shift;
   my $option = shift;
   my $value = shift;
   #my ( $section, $parameter ) = split( ".", $option );

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{STATE_FILE}; 
 
   my $STATE = $self->{STATE};
   unless ( defined $STATE ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not write to $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   $STATE->param( $option, $value );
   my $status = $STATE->save( $config_file );
   
   #$STATE->close();
   #undef $STATE;
   
   return ESTAR__OK;

} 

sub write_state {
   my $self = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{STATE_FILE}; 

   my $STATE = $self->{STATE};
   unless ( defined $STATE ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not write to $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   my $status = $STATE->save( $config_file );
   #$STATE->close();
   #undef $STATE;
   
   return $status;
}   

sub get_nodes {
   my $self = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{CONFIG_FILE}; 

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 
      
   my %hash = %{$CONFIG->get_block( "nodes" )};
   #$CONFIG->close();
   #undef $CONFIG;
     
   # loop through configuration hash
   my @NODES;
   foreach my $key ( sort keys %hash ) {
      # grab the node name from the key value
      push( @NODES, $hash{$key} ); 
   }
   
   return @NODES;
   
} 

sub get_node_names {
   my $self = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{CONFIG_FILE}; 

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 
      
   my %hash = %{$CONFIG->get_block( "nodes" )};
   #$CONFIG->close();
   #undef $CONFIG;
     
   # loop through configuration hash
   my @NAMES;
   foreach my $key ( sort keys %hash ) {
      # grab the node name from the key value
      push( @NAMES, $key ); 
   }
   
   return @NAMES;


}

sub get_useragents {
   my $self = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{CONFIG_FILE}; 

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 
      
   my %hash = %{$CONFIG->get_block( "useragents" )};
   #$CONFIG->close();
   #undef $CONFIG;
     
   # loop through configuration hash
   my @UAS;
   foreach my $key ( sort keys %hash ) {
      # grab the node name from the key value
      push( @UAS, $hash{$key} ); 
   }
   
   return @UAS;
   
} 


sub get_useragent_names {
   my $self = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{CONFIG_FILE}; 

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 
      
   my %hash = %{$CONFIG->get_block( "useragents" )};
   #$CONFIG->close();
   #undef $CONFIG;
     
   # loop through configuration hash
   my @UA_NAMES;
   foreach my $key ( sort keys %hash ) {
      # grab the node name from the key value
      push( @UA_NAMES, $key ); 
   }
   
   return @UA_NAMES;
   
} 

sub make_directories {
   my $self = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   my $config_file = $self->{CONFIG_FILE}; 

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   my $state_file = $self->{STATE_FILE}; 

   my $STATE = $self->{STATE};
   unless ( defined $STATE ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $state_file";
      $log->error( $error );
      return undef;      
   }   
    
   # E S T A R   D A T A   D I R E C T O R Y 

   # Grab the $ESTAR_DATA enivronment variable and confirm that this directory
   # exists and can be written to by the user, if $ESTAR_DATA isn't defined we
   # fallback to using the temporary directory /tmp.

   # Grab something for DATA directory
   if ( defined $ENV{"ESTAR_DATA"} ) {

      if ( opendir (DIR, File::Spec->catdir($ENV{"ESTAR_DATA"}) ) ) {
         # default to the ESTAR_DATA directory
         $CONFIG->param("dir.data", File::Spec->catdir($ENV{"ESTAR_DATA"}) );
         closedir DIR;
         $log->debug("Verified \$ESTAR_DATA directory " . $ENV{"ESTAR_DATA"});
         
         
      } else {
         # Shouldn't happen?
         my $error = "Cannot open $ENV{ESTAR_DATA} for incoming files";
         $log->error($error);
         
         return undef;
      }  
         
   } elsif ( opendir(TMP, File::Spec->tmpdir() ) ) {
         # fall back on the /tmp directory
         $CONFIG->param("dir.data", File::Spec->tmpdir() );
         closedir TMP;
         $log->debug("Falling back to using /tmp as \$ESTAR_DATA directory");
                  
   } else {
      # Shouldn't happen?
      my $error = "Cannot open any directory for incoming files.";
      $log->error($error);
      
      return undef;
   } 

   # A G E N T   S T A T E  D I R E C T O R Y 

   # This directory where the agent caches its Observation 
   # objects between runs
   my $state_dir = 
     File::Spec->catdir( Config::User->Home(), ".estar",  
                         $process->get_process(),  "state");

   if ( opendir ( SDIR, $state_dir ) ) {
  
     # default to the ~/.estar/$process/state directory
     $CONFIG->param("dir.cache", $state_dir );
     $STATE->param("dir.cache", $state_dir );
     $log->debug("Verified state directory ~/.estar/" .
                 $process->get_process() . "/state");
     closedir SDIR;
          
   } else {
     # make the directory
     mkdir $state_dir, 0755;
     if ( opendir (SDIR, $state_dir ) ) {
        # default to the ~/.estar/$process/state directory
        $CONFIG->param("dir.cache", $state_dir );
        $STATE->param("dir.cache", $state_dir );
        closedir SDIR;  
        $log->debug("Creating state directory ~/.estar/" .
                 $process->get_process() . "/state");
                                  
     } else {
        # can't open or create it, odd huh?
        my $error = "Cannot make directory " . $state_dir;
        $log->error( $error );
        
        return undef;  
     }
   } 
            
   # A G E N T   T E M P  D I R E C T O R Y 

   # This directory where the agent drops temporary files
   my $tmp_dir = 
      File::Spec->catdir( Config::User->Home(), ".estar",  
                      $process->get_process(), "tmp");

   if ( opendir ( TDIR, $tmp_dir ) ) {
  
     # default to the ~/.estar/$process/tmp directory
     $CONFIG->param("dir.tmp", $tmp_dir );
     $STATE->param("dir.tmp", $tmp_dir );
     $log->debug("Verified tmp directory ~/.estar/" .
                 $process->get_process() . "/tmp");
     closedir TDIR;
          
   } else {
     # make the directory
     mkdir $tmp_dir, 0755;
     if ( opendir (TDIR, $tmp_dir ) ) {
        # default to the ~/.estar/$process/tmp directory
        $CONFIG->param("dir.tmp", $tmp_dir );
        $STATE->param("dir.tmp", $tmp_dir );
        closedir TDIR;  
        $log->debug("Creating tmp directory ~/.estar/" .
                 $process->get_process() . "/tmp");
                                  
     } else {
        # can't open or create it, odd huh?
        my $error = "Cannot make directory " . $tmp_dir;
        $log->error( $error );
        
        return undef;
     }
   }  
   
   return 1;

}


sub get_data_dir {
   my $self = shift;

   my $config_file = $self->{CONFIG_FILE}; 

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   #$log->warn("Data dir is " . $CONFIG->param("dir.data") );
   return $CONFIG->param("dir.data");    
}

sub get_state_dir {
   my $self = shift;

   my $config_file = $self->{CONFIG_FILE}; 

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   #$log->warn("State dir is " . $CONFIG->param("dir.cache") );
   return $CONFIG->param("dir.cache");    
}   

sub get_tmp_dir {
   my $self = shift;

   my $config_file = $self->{CONFIG_FILE}; 

   my $CONFIG = $self->{CONFIG};
   unless ( defined $CONFIG ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );
      return undef;      
   } 

   #$log->warn("Temporary dir is " . $CONFIG->param("dir.tmp") );
   return $CONFIG->param("dir.tmp");    
   
}   

1;
