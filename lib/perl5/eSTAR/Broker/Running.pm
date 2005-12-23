package eSTAR::Broker::Running;


# L O A D   M O D U L E S --------------------------------------------------

use strict;
use vars qw/ $VERSION /;
use subs qw/ new swallow_messages swallow_collected swallow_tids
             list_messages add_message register_tid deregister_tid 
	     set_collected garbage_collect /;

use threads;
use threads::shared;

use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:status/;

'$Revision: 1.10 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

# C O N S T R U C T O R ----------------------------------------------------

# is a single instance class, can only be once instance for the entire
# application. Use get_reference() to grab a reference to the object.
my $SINGLETON;

sub new {
  return $SINGLETON if defined $SINGLETON;

  my $proto = shift;
  my $class = ref($proto) || $proto;

  # bless the query hash into the class
  $SINGLETON = bless { PROCESS      => undef,
                       TAGNUM       => undef,
                       MESSAGES     => undef,
		       COLLECTED    => undef,
		       TIDS         => undef  }, $class;
  
  # Configure the object
  $SINGLETON->configure( @_ );
  
  return $SINGLETON;
}

sub get_reference {
  return $SINGLETON if defined $SINGLETON;
  return undef;
}

sub configure {
  my $self = shift;

  # grab the process name
  my $process = eSTAR::Process::get_reference(); 
  $self->{PROCESS} = $process->get_process();
  
  # DEBUGGING
  # ---------
  
  # debugging is on by default
  $self->{TOGGLE} = ESTAR__DEBUG;
 
  # UNIQUE TAG NUMBER
  # -----------------

  # Tag number identifying each individual instance of the class
  my $tagid = sprintf( '%.0f', rand( 1000 ) );
  $self->{TAGNUM} = "TagID#" . $self->{PROCESS} . "#$tagid";

}

# METHODS ----------------------------------------------------------------


sub swallow_messages {
  my $self = shift;
  my $hash = shift;
   
  share( %$hash ); 
  $self->{MESSAGES} = $hash; 
  
}     

sub swallow_collected {
  my $self = shift;
  my $hash = shift;
   
  share( %$hash ); 
  $self->{COLLECTED} = $hash; 
  
}

sub swallow_tids {
  my $self = shift;
  my $array = shift;
   
  share( @$array ); 
  $self->{TIDS} = $array; 
  
}

sub list_messages {
  my $self = shift;
  my @messages;
  
  { 
     lock( %{$self->{MESSAGES}} );
     foreach my $key ( sort keys %{$self->{MESSAGES}} ) {
        push @messages, $key;
     } 
  } # implict unlock() here, end of locking block
  
  return @messages;
} 

sub add_message {
  my $self = shift;         
  my $id = shift;
  my $message = shift;
  
  {
     lock( %{$self->{MESSAGES}} );
     ${$self->{MESSAGES}}{$id} = $message;
  }     
}

sub register_tid {
  my $self = shift;
  my $tid = shift;
  
  {
    lock( @{$self->{TIDS}} );
    push @{$self->{TIDS}}, $tid;
  }  
}

sub deregister_tid {
  my $self = shift;
  my $tid = shift;
  
  {
    lock( @{$self->{TIDS}} );
    foreach my $i ( 0 ... $#{$self->{TIDS}} ) {
       if ( ${$self->{TIDS}} == $tid ) {
             splice @{$self->{TIDS}}, $i, 1;
	     last;
        }
    }		     
  }
}  

sub list_tids {
  my $self = shift;
  my @tids;
  {
    lock( @{$self->{TIDS}} );
    foreach my $i ( 0 ... $#{$self->{TIDS}} ) {
       push @tids, ${$self->{TIDS}}[$i];
    }		     
  }
}    
    
sub set_collected {
  my $self = shift;
  my $tid = shift;
  my $id = shift;

}

sub garbage_collect {

} 
  
1;

                                                                  
