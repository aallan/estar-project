package eSTAR::UA::Algorithm::SingleExposure;

use strict;
use vars qw/ $VERSION /;

'$Revision: 1.1 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

use threads;
use threads::shared;
use Fcntl ':flock';
use Carp;

use eSTAR::UA::Constants qw/:status/;
use eSTAR::Util;

# C O N S T R U C T O R ----------------------------------------------------

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;

  # bless the header block into the class
  my $block = bless { OBS => undef }, $class;

  return $block;

}

# M E T H O D S -------------------------------------------------------------

sub process_data {
  my $self = shift;
  my $id = shift;

  $main::log->debug("Called process_data() from \$tid = ".threads->tid());
  
  # THAW OBSERVATION
  # ================
  
  # thaw the observation object
  my $observation_object = thaw( $id );
  return UA__ERROR unless defined $observation_object;
  
  # stuff into object 
  $self->{OBS} = $observation_object;
  
  # PROCESS DATA
  # ============

  $main::log->debug("No processing needed...");
  
  
  # FREEZE OBSERVATION
  # ==================
  
  # freeze the observation object
  my $status = freeze( $self->{OBS} ); 
  if ( $status == UA__ERROR ) {
     $main::log->warn( 
         "Warning: Problem re-serialising the \$observation_object");
     return UA__ERROR;    
  }  
    
  return UA__OK;
}

              
1;
