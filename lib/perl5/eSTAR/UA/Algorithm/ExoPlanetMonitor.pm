package eSTAR::UA::Algorithm::ExoPlanetMonitor;

use strict;
use vars qw/ $VERSION /;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

use threads;
use threads::shared;
use Fcntl qw(:DEFAULT :flock);
use Carp;

use eSTAR::Constants qw/:status/;
use eSTAR::Util;
use eSTAR::Config;

my ( $log, $config );

# C O N S T R U C T O R ----------------------------------------------------

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # bless the header block into the class
  my $block = bless { OBS => undef }, $class;
  $log = eSTAR::Logging::get_reference();
  $config = eSTAR::Config::get_reference();

  return $block;

}

# M E T H O D S -------------------------------------------------------------

sub process_data {
  my $self = shift;
  my $id = shift;

  $log->debug("Called process_data() from \$tid = ".threads->tid());
  
  # THAW OBSERVATION
  # ================
  
  # thaw the observation object
  my $observation_object = eSTAR::Util::thaw( $id );
  return ESTAR__ERROR unless defined $observation_object;
  
  # stuff into object 
  $self->{OBS} = $observation_object;
  
  # PROCESS DATA
  # ============

  $log->debug("No processing needed...");
  
  
  # FREEZE OBSERVATION
  # ==================
  
  # freeze the observation object
  my $status =  eSTAR::Util::freeze( $id, $self->{OBS} ); 
  if ( $status == ESTAR__ERROR ) {
     $log->warn( 
         "Warning: Problem re-serialising the \$observation_object");
     return ESTAR__ERROR;    
  }  
    
  return ESTAR__OK;
}

              
1;
