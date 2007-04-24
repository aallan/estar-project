package eSTAR::UA::Algorithm::VariableMonitor;

use strict;
use vars qw/ $VERSION /;

'$Revision: 1.2 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

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
   my $msg_type = shift;

   $log->debug("Called process_data() from \$tid = ".threads->tid());
   $log->debug("Message is of type '$msg_type'");

   # Ignore any messages not dealing with an actual submitted request...
   return if ( $msg_type eq 'confirmation' || $msg_type eq 'score');


   # THAW OBSERVATION
   # ================

   # thaw the observation object
   my $observation_object = eSTAR::Util::thaw( $id );
   return ESTAR__ERROR unless defined $observation_object;

   # stuff into object 
   $self->{OBS} = $observation_object;

   # PROCESS DATA
   # ============

   # Connect to adaptive_vs_scheduler TCP/IP server and send observation
   # information...

   my $tcp_host = 'estar.astro.ex.ac.uk';
   my $tcp_port = 6666;

   my $outgoing = IO::Socket::INET->new("$tcp_host:$tcp_port")
      or die "Couldn't connect to server: $@";
   $outgoing->autoflush(1);

   print $outgoing "target = " . $self->{OBS}->score_request->target . "\n";
   print $outgoing "id = "     . $self->{OBS}->id . "\n";
   print $outgoing "status = " . $self->{OBS}->status . "\n";
   print $outgoing "type = "   . $self->{OBS}->type . "\n";   

   
   my @time_constraints = $self->{OBS}->score_request->time_constraint;
   print $outgoing "start time = $time_constraints[0]\n";
   print $outgoing "end time = $time_constraints[1]\n";   
   print $outgoing "message type = $msg_type\n";
   
   if ( $msg_type eq 'observation' ) {
      print $outgoing "completion time = "   
                      . $self->{OBS}->observation->completion_time . "\n";



      # Extract and send the timestamp back to the driver code...
      my @metadata = $self->{OBS}->observation->data;
      my @timestamps = extract_fits_timestamp(@metadata);
      print $outgoing "FITS timestamp = $_\n" for @timestamps;

   }
   elsif ( $msg_type eq 'update' ) {
      # This is to try and catch the peculiar situation where the update message
      # made it, but no completion message ever arrived. Since we only make
      # one observation per block, if there's data here, then we want it - it
      # represents the actual observation.

      print $outgoing "update time = "
                      . $self->{OBS}->update->completion_time . "\n";
                      
      # Extract and send the timestamp back to the driver code...
      my @metadata = $self->{OBS}->update->data;
      my @timestamps = extract_fits_timestamp(@metadata);
      if ( @timestamps ) {
         print $outgoing "FITS timestamp = $_\n" for @timestamps;
      }
      else {
         print $outgoing "FITS timestamp = [none]\n";      
      }

  } 
   elsif ( $msg_type eq 'reject'  || $msg_type eq 'failed' 
           || $msg_type eq 'fail' || $msg_type eq 'abort' 
           || $msg_type eq 'incomplete' ) {
      print $outgoing "FITS timestamp = [none]\n";
   }


   $outgoing->shutdown(1);
   $log->debug("Shutdown outbound connection to user agent TCP/IP server...");


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


sub extract_fits_timestamp {
   my @metadata = @_;
   my @timestamps;

   foreach my $data_element ( @metadata ) {
      if ( my $fits_header = $data_element->{Header} ) {
         $log->debug("Found a fits header...");

         # Extract the timestamp from the fits header...
         my ($obs_timestamp) = $fits_header =~ m{DATE-OBS=\s*'([^']+)};

         push @timestamps, $obs_timestamp;
      }      
   }

   return @timestamps;
}
              
1;
