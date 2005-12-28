package eSTAR::Broker::Running;


# L O A D   M O D U L E S --------------------------------------------------

use strict;
use vars qw/ $VERSION /;
use subs qw/ new swallow_messages swallow_collected swallow_tids
             get_message list_messages add_message register_tid 
             deregister_tid list_collections set_collected is_collected 
             garbage_collect list_connections dump_tids dump_self 
             delete_messages /;

use threads;
use threads::shared;

use eSTAR::Error qw /:try/;
use eSTAR::Constants qw /:status/;
use Data::Dumper;

'$Revision: 1.19 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

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
                       MESSAGES     => (),
		       COLLECTED    => (),
		       TIDS         => ()  }, $class;
  
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
  my $hash = shift;
   
  share( %$hash ); 
  $self->{TIDS} = $hash; 
  
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

sub get_message {
  my $self = shift;         
  my $id = shift;
 
  my $xml;
  {
     lock( %{$self->{MESSAGES}} );
     $xml = ${$self->{MESSAGES}}{$id};
  } 
  
  return $xml;    
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
  my $server = shift;
  
  {
     lock( %{$self->{TIDS}} );
     ${$self->{TIDS}}{$tid} = $server;
  }  

}

sub deregister_tid {
  my $self = shift;
  my $tid = shift;
  
  {
    lock( %{$self->{TIDS}} );
    delete ${$self->{TIDS}}{$tid};
    	     
  }
  {
    lock( %{$self->{COLLECTED}} );
    delete ${$self->{COLLECTED}}{$tid};
  }    
  
  
}  

sub list_tids {
  my $self = shift;
  my @tids;
  {
    lock( %{$self->{TIDS}} );
    @tids = keys %{$self->{TIDS}}		     
  }
  return @tids;
}    


sub list_connections {
  my $self = shift;
  my @values;
  {
    lock( %{$self->{TIDS}} );
    @values = values %{$self->{TIDS}}		     
  }
  return @values;
}    

sub dump_tids {
  my $self = shift;
  my %hash;
  {
    lock( %{$self->{TIDS}} );
    %hash = %{$self->{TIDS}}	     
  }
  return %hash;
}
    
sub set_collected {
  my $self = shift;
  my $tid = shift;
  my $id = shift;
  
  {
  
     # if would be better if we could use a hash of arrays here, but the
     # array reference would have to be dynamically created after the threads
     # have already detached and wouldn't be shared (in reality we'd get a 
     # inapprorpaiate scalar reference error and the thread wou;d die since
     # we'd be creating an non-shared array reference inside an shared hash)
     #
     # so we're going to do it the hard way and use a string, hopefully a space
     # shouldn't turn up in an IVORN so this should be a good separator.
     lock( %{$self->{COLLECTED}} );
     my $string = ${$self->{COLLECTED}}{$tid};
     $string = $string . " " . $id;
     $string =~ s/^\s+//;
     $string =~ s/\s+$//;
     ${$self->{COLLECTED}}{$tid} = $string;
  }   

}

sub is_collected {
  my $self = shift;
  my $tid = shift;
  my $id = shift;
  
  my $flag;
  {
     lock( %{$self->{COLLECTED}} );
     my @array = split " ", ${$self->{COLLECTED}}{$tid};
     foreach my $i ( 0 ... $#array ) {
        $flag = 1 if $array[$i] eq "$id";
     }	     
  } 
  return $flag;
}  

sub list_collections {
  my $self = shift;
  
  my %hash;
  {
     lock( %{$self->{COLLECTED}} );
     foreach my $key ( keys %{$self->{COLLECTED}} ) {
        my $string = ${$self->{COLLECTED}}{$key};
        my @array = split " ", $string;
        $hash{$key} = [ @array ]; 
     }
  }   
  return %hash;
}

sub garbage_collect {
  my $self = shift;
  
  {
     lock( %{$self->{MESSAGES}} );
     lock( %{$self->{COLLECTED}} );
     
     my $num_tids = scalar( $self->list_tids() );
     
     # Loop through all current messages
     foreach my $id ( keys %{$self->{MESSAGES}} ) {
        
        # Loop through each TID's list of collected messages
        my $counter = 0;
        foreach my $tid ( keys %{$self->{COLLECTED}} ) {
           my @array = split " ", ${$self->{COLLECTED}}{$tid};
           foreach my $i ( 0 ... $#array ) {
           
              # increment collected counter if the message has been
              # collected by the TID we're currently looking at
              $counter = $counter + 1 if $array[$i] eq $id;
           }  
        }
        
        # If the number TIDs which have collected this message is the
        # same as the total number of TIDs we can garbage collect        
        if ( $counter == $num_tids ) {
        
            # remove from MESSAGES
            delete ${$self->{MESSAGES}}{$id};
            
            # remove from all strings
            foreach my $tid ( keys %{$self->{COLLECTED}} ) {
               ${$self->{COLLECTED}}{$tid} =~ s/$id//;
               ${$self->{COLLECTED}}{$tid} =~ s/\s+/ /;
            }   
        }
     }  
     
  } # unlock the shared variables

} 

sub delete_messages {
  my $self = shift;
  
  # returns the number of deleted messages, however it will only delete 
  # the message hash if there are no current client connections, otherwise 
  #return undef. Safety first people...
  my $messages = 0;
  {
     lock( %{$self->{MESSAGES}} );
     
     my $num_tids = scalar( $self->list_tids() );
     unless( $num_tids == 0 ) {
        return undef;
     }   
     
     # Loop through all current messages
     foreach my $id ( keys %{$self->{MESSAGES}} ) {
        
        # remove from MESSAGES
        delete ${$self->{MESSAGES}}{$id};
        $messages = $messages + 1;
      
     }  
     
  } # unlock the shared variables

  return $messages;
} 

sub dump_self {
   my $self = shift;
   return Dumper( $self );
}   
   
  
1;

                                                                  
