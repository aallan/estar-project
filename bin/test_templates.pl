#!/jac_sw/estar/perl-5.8.6/bin/perl
  
  #use strict;
  
  use vars qw /$VERSION/;

  $VERSION = '0.1';

  #
  # General modules
  use Getopt::Long;

  #
  # eSTAR modules
  use lib $ENV{"ESTAR_PERL5LIB"};     
  use eSTAR::Util;
  use eSTAR::Logging;
  use eSTAR::Process;
  use eSTAR::Config;
  use eSTAR::Error qw /:try/;
  use eSTAR::Constants qw/:status/;
  use eSTAR::Mail;
  use eSTAR::JACH::Util;

  # 
  # JACH modules
  use lib $ENV{"ESTAR_OMPLIB"};
  use OMP::SciProg;
  use OMP::SpServer;

  my $process = new eSTAR::Process( "jach_agent" );  
  $process->set_version( $VERSION );
  print "Starting logging...\n\n";
  $log = new eSTAR::Logging( $process->get_process() );
  $log->header("Starting JACH Template Test: Version $VERSION");
  my $config = new eSTAR::Config(  );  

  # Start of main body

  unless ( scalar @ARGV >= 2 ) {
     die "USAGE: $0 -project id -pass password\n";
  }

  my ( $project, $password );   
  my $status = GetOptions( "project=s"    => \$project,
                           "pass=s"       => \$password );

  # retrieve the science program  
  my $sp;
  try {                                  
     $sp = OMP::SpServer->fetchProgram( $project, $password, 1 );
     unless ( $sp ) {
        throw eSTAR::Error::FatalError( 
            "OMP::SpServer()->fetchProgram returned undef..."); 
     }
  } otherwise {
     my $error = shift;
     $log->error( 
       "Error: Unable to retrieve science programme from OMP");
     $log->error( "Error: $error" );
     $flag = 1;
  }; 


  # scan through MSBs
  $log->debug( "Scanning through MSB templates..." );
  
  my $template_initial, $template_follow;
  for my $m ( $sp->msb() ) {
     $log->debug( "Found template " . $m->msbtitle() );

     my $looking_for = "InitialBurstFollowup";
     my $template_initial = has_blank_targets( $m, $looking_for );
     $looking_for = "BurstFollowup";
     my $template_follow = has_blank_targets( $m, $looking_for ); 
     
  }

  unless ( defined $template_initial ) {
        
     # return the RTML document
     $log->warn("Warning: InitialBurstFollowup template not found");
     $log->warn( 
           "Warning: Unable to find a matching template MSB");
  } else {
     $log->print("Verified InitialBurstFollowup template MSB");
  }      

  unless( defined $template_follow ) {
        
     # return the RTML document
     $log->warn("Warning: BurstFollowup template not found");
     $log->warn( 
           "Warning: Unable to find a matching template MSB");
  } else {
     $log->print("Verified BurstFollowup template MSB");    
  }


  exit;


sub has_blank_targets {
   my $m = shift;
   my $looking_for = shift;
   
   my $template = undef;
   if ( $m->msbtitle()  =~ /\b$looking_for/ ) {
    
      $log->debug( "Matched '" . $m->msbtitle() . "'" );
      
      # Grab the instrument from this MSB
      my $minfo = $m->info();
      my $msb_inst = $minfo->instrument();
      $log->debug( "This MSB is for $msb_inst" );
      
      my $curr_inst = eSTAR::JACH::Util::current_instrument( "UKIRT" );
      $log->debug( "Current instrument is $curr_inst" );
      
      if ( $msb_inst eq $curr_inst ) {
         $log->debug( "$loking_for MSB and current instrument match..." );
      
         # If it has blank targets it is a template MSB
         if ( $m->hasBlankTargets() ) {

           $log->debug( "Confirmed that this is a template MSB" );
           $template = $m;
           last;
         } else {
           $log->warn( "Warning: $looking_for MSB does not have blank targets" );
           last;
         }
      } else {
         $log->debug( "$looking_for MSB and current instrument do not match..." );
      }   
       
   }
   return $template;
}     
