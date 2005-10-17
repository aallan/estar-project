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
  $log->print( "Retrieving project $project from OMP..." );
  
  my $sp;
  try {                                  
     $sp = OMP::SpServer->fetchProgram( $project, $password, 1 );
     unless ( $sp ) {
        $log->error("OMP::SpServer()->fetchProgram returned undef..."); 
        exit;
     }
  } otherwise {
     my $error = shift;
     $log->error( 
       "Error: Unable to retrieve science programme from OMP");
     $log->error( "Error: $error" );
     exit;
  }; 
 
  $log->print( "There are " . scalar( $sp->msb() ) . 
      " MSBs in the science programme" );

  
  # scan through MSBs
  $log->print( "Scanning through MSB templates..." );
  my $name = "InitialBurstFollowup";
  my $template;
  for my $m ( $sp->msb() ) {
     $log->debug( "Found MSB '" . $m->msbtitle() . "'" );
     if ( $m->msbtitle()  =~ /\b$name/ ) {
    
        $log->debug("Matched '". $m->msbtitle()."' as a possible template...");
      
        # Grab the instrument from this MSB
        my $minfo = $m->info();
        my $msb_inst = $minfo->instrument();
        $log->debug( "This MSB is for $msb_inst" );
      
        my $curr_inst = eSTAR::JACH::Util::current_instrument( "UKIRT" );
        $log->debug( "Current instrument is $curr_inst" );
      
        if ( $msb_inst eq $curr_inst ) {
           $log->debug( "MSB and current instrument match..." );
      
           # If it has blank targets it is a template MSB
           if ( $m->hasBlankTargets() ) {

             $log->debug( "This MSB has blank targets..." );
             $log->debug( "Confirmed that this is a template MSB" );
             $template = $m;
             last;
           } else {
             $log->warn( "Warning: MSB does not have blank targets" );
             last;
           }
        } else {
           $log->warn( "Warning: MSB and current instrument do not match..." );
        }   
       
     } else {
        $log->debug( "Discarding '" . $m->msbtitle() . "'" );
     }  
  }
  $log->print("All MSBs have now been checked...");

  exit;

  unless ( defined $template ) {
        
     # return the RTML document
     $log->warn("Warning: Template for '" . $name . "' not found");
     $log->warn("Warning: Unable to find a matching template MSB");
  } else {
     $log->print("Verified template for '" . $name . "' MSB");
  }      

  exit;
