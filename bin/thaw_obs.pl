#!/software/perl-5.8.6/bin/perl
  
  #use strict;
  use lib $ENV{"ESTAR_PERL5LIB"};     
  
  # general modules
  use Data::Dumper;
  use File::Spec;
  
  # eSTAR modules
  use eSTAR::Observation;
  use eSTAR::RTML;
  use eSTAR::RTML::Build;
  use eSTAR::RTML::Parse;

  # Astro modules
  use Astro::FITS::Header;
  use Astro::Catalog;


  die "USAGE: $0 filename\n" unless ( scalar @ARGV == 1 );
  my $file = $ARGV[0];
 
  $file = File::Spec->catfile( 
          "/home/$ENV{USER}/.estar/user_agent/state/", $file ); 
  unless ( open ( FILE, $file ) ) {
     print "Error: Can not open file $file\n";
     exit;
  }
  
  undef $/;
  my $string = <FILE>;    
  close(FILE);
  
  # check we have a valid observation object
  print "Thawing observation from file...\n";
  my $observation_object;
  $observation_object = eval $string;
  if ( $@ ) {
     die "Error: $@\n";
  } else {   
     print "Restored observation " . $observation_object->id() . "\n";
  } 
  
  # check we have valid FITS headers
  my $header = $observation_object->fits_header();  
  my $date = $header->itembyname('DATE-OBS');
  if ( $@ ) {
     die "Error: $@\n";
  } else {   
     print "\nObservation taken at " . $date->value() . "\n";      
  } 
 
  # grab node carried out on and score
  my $best_node = $observation_object->node();
  if ( $@ ) {
     die "Error: $@\n";
  }
  
  my $score_request = $observation_object->score_request();
  if ( $@ ) {
     die "Error: $@\n";
  }
  my $target_score = $score_request->target();
  my $ra_score = $score_request->ra();
  my $dec_score = $score_request->dec();
  print "Target was $target_score ($ra_score, $dec_score)\n";
    
  my $score_replies = $observation_object->score_reply();
  if ( $@ ) {
     die "Error: $@\n";
  }
  
  my $score_reply = $$score_replies{$best_node};
  my $best_score = $score_reply->score();

   
     
  # check we have valid FITS file
  my $url = $observation_object->fits_url();
  if ( $@ ) {
     die "Error: $@\n";
  } else {   
     print "URL is " . $url . "\n";      
  }     
  my $fits = $observation_object->fits_file();
  if ( $@ ) {
     die "Error: $@\n";
  } else {   
     print "Local copy at " . $fits . "\n";      
  }  
    
  # check we have a valid cluster catalogue
  my $cluster = $observation_object->catalog();
  my $size = $cluster->sizeof();
  if ( $@ ) {
     die "Error: $@\n";
  } else {   
     print "Object point source catalogue has " . $size . " lines\n";      
  }   
 
  # check we have an 'observation' document
  my $obs_doc = $observation_object->observation();
  if ( $@ ) {
     die "Error: $@\n";
  }

  # print the summary
  print "\nSummary\n-------\n";
  print $observation_object->summary() . "\n";


  exit;
  
