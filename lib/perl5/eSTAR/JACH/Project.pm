package eSTAR::JACH::Project;


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
@EXPORT = qw/ get_project set_project write_project reread get_reference /;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

my $SINGLETON;

my ($log, $process);
sub new {
   return $SINGLETON if defined $SINGLETON;

   my $proto = shift;
   my $class = ref($proto) || $proto;   
   $SINGLETON = bless { PROJECT      => undef,
                        PROJECT_FILE => undef }, $class;

   $log = eSTAR::Logging::get_reference();
   $process = eSTAR::Process::get_reference();
   
   $SINGLETON->{PROJECT_FILE} = 
         File::Spec->catfile( Config::User->Home(), '.estar', 
                              $process->get_process(), 'project.dat' ); 
   $SINGLETON->{PROJECT} = create_ini_file( $SINGLETON->{PROJECT_FILE} );
 
   return $SINGLETON;
}

sub get_reference {
  return $SINGLETON if defined $SINGLETON;
  return undef;
}


sub reread {
   my $self = shift;
   
   my $log = eSTAR::Logging::get_reference();
   
   $log->warn( "Warning: Forced read of $self->{PROJECT_FILE}" );
   $self->{PROJECT}->read( $self->{PROJECT_FILE} );
 
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
sub get_project {
   my $self = shift;
   my $option = shift;
   #my ( $section, $parameter ) = split( ".", $option );

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{PROJECT_FILE};
 
   $log->debug("Looking up $option in $config_file");
   
   my $PROJECT = $self->{PROJECT};
   unless ( defined $PROJECT ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not read from $config_file";
      $log->error( $error );     
      return undef;      
   } 
   
   #unless ( $CONFIG->param($option ) ) {
   #   $log->error("Error: Can not get $option from options.dat file");
   #   return ESTAR__ERROR;   
   #}
   
   if ( defined $PROJECT->param( $option ) ) {
      $log->debug( $option . " = " .  $PROJECT->param( $option ) ); 
   } else {
      $log->warn( "Warning: $option is currently undefined" );
      
   }
   my $value = $PROJECT->param( $option );
   #$CONFIG->close();
   #undef $CONFIG;
   
   return $value;
} 

# set an option in the $CONFIG file
sub set_project {
   my $self = shift;
   my $option = shift;
   my $value = shift;
   #my ( $section, $parameter ) = split( ".", $option );

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{PROJECT_FILE};

   my $PROJECT = $self->{PROJECT};
   unless ( defined $PROJECT ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not write to $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   $PROJECT->param( $option, $value );
   my $status = $PROJECT->save( $config_file );
   #$CONFIG->close();
   #undef $CONFIG;
   
   return ESTAR__OK;

} 

sub write_project {
   my $self = shift;

   # grab references to single instance objects
   my $log = eSTAR::Logging::get_reference();
   my $process = eSTAR::Process::get_reference();

   # grab users home directory and define options filename
   my $config_file = $self->{PROJECT_FILE};

   my $PROJECT = $self->{PROJECT};
   unless ( defined $PROJECT ) {
      # can't read/write to options file, bail out
      my $error = "FatalError: Can not write to $config_file";
      $log->error( $error );
      return undef;      
   } 
   
   my $status = $PROJECT->save( $config_file );
   #$CONFIG->close();
   #undef $CONFIG;
   
   return $status;
}   

1;
