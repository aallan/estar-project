package eSTAR::Config;


use strict;
use warnings;

require Exporter;
use Config::Simple;
use Fcntl qw(:DEFAULT :flock);
use Data::Dumper;

#use eSTAR::Logging;
#use eSTAR::Process;
use eSTAR::Constants qw/:all/;

use vars qw/$VERSION @EXPORT @ISA/;

@ISA = qw/Exporter/;
@EXPORT = qw/ config get_option set_op;tion write_option
              state get_state set_state write_state
              get_nodes get_reference/;

'$Revision: 1.2 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

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

sub config {
   my $self = shift;
   $self->{CONFIG} = shift;   
}

sub state {
   my $self = shift;
   return $self->{PROCESS};
}   


sub reread {
   my $self = shift;
   
   my $log = eSTAR::Logging::get_reference();
   
   $log->warn( "Warning: Forced read of $self->{CONFIG_FILE}" );
   $self->{CONFIG}->read( $self->{CONFIG_FILE} );
   
   $log->warn( "Warning: Forced read of $self->{STATE_FILE}" );
   $self->{STATE}->read( $self->{STATE_FILE} );
 
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
      
      $CONFIG = new Config::Simple( filename => $file,
                                    syntax   => 'ini', 
                                    mode     => O_RDWR );
   } else {
      $log->warn("Warning: Creating new config file $file");
      $CONFIG = new Config::Simple( syntax   => 'ini', 
                                    mode     => O_RDWR|O_CREAT );
      
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

1;
