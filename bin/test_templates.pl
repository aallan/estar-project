#!/software/perl-5.8.6/bin/perl
  
  #use strict;
  
  #use SOAP::Lite +trace => all;
  use SOAP::Lite;
  
  use Digest::MD5 'md5_hex';
  use URI;
  use HTTP::Cookies;
  use Getopt::Long;
  use Net::Domain qw(hostname hostdomain);
  use Socket;

  #
  # eSTAR modules
  use lib $ENV{"ESTAR_PERL5LIB"};     
  use eSTAR::Util;

  # 
  # JACH modules
  use lib $ENV{"ESTAR_OMPLIB"};
  use OMP::SciProg;
  use OMP::SpServer;

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
  $log->debug( "Scanning through MSB templates looking for '" .
                $parsed->targetident() . "'" );
  
  my $template_initial, $template_follow;
  for my $m ( $sp->msb() ) {
     $log->debug( "Found template " . $m->msbtitle() );

     my $looking_for = "InitialBurstFollowup";
     my $template_initial = has_blank_targets( $m, $looking_for );
     $looking_for = "InitialBurstFollowup";
     my $template_follow = has_blank_targets( $m, $looking_for ); 
     
  }

  unless ( defined $template_initial ) {
        
     # return the RTML document
     $log->debug("Rejecting observation initial request...");
     $log->warn( 
           "Warning: Unable to find a matching template MSB");
  }   

  unless ( defined $template_follow ) {
        
     # return the RTML document
     $log->debug("Rejecting observation initial request...");
     $log->warn( 
           "Warning: Unable to find a matching template MSB");
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
         $log->debug( "MSB and current instrument match..." );
      
         # If it has blank targets it is a template MSB
         if ( $m->hasBlankTargets() ) {

           $log->debug( "Confirmed that this is a template MSB" );
           $template = $m;
           last;
         } else {
           $log->warn( "Warning: MSB does not have blank targets" );
           last;
         }
      } else {
         $log->debug( "MSB and current instrument do not match..." );
      }   
       
   }
   return $template;
}     
