package eSTAR::UA::Algorithm::PhotometryFollowup;

use strict;
use vars qw/ $VERSION /;

'$Revision: 1.6 $ ' =~ /.*:\s(.*)\s\$/ && ($VERSION = $1);

use threads;
use threads::shared;
use Carp;
use File::Spec;
use SOAP::Lite;
use URI;
use HTTP::Cookies;
use LWP::UserAgent;
use Fcntl qw(:DEFAULT :flock);

use eSTAR::Constants qw/:all/;
use eSTAR::UA::Handler;
use eSTAR::Error qw /:try/;
use eSTAR::Util;
use eSTAR::Config;

use Astro::Catalog;
use Astro::Catalog::Query::USNOA2;
use Astro::Corlate;

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
  my $self     = shift;
  my $id       = shift;
  my $obs_type = shift;
      

  $log->debug("Called process_data() from \$tid = ".threads->tid());

  # We're only interested in processing messages of type 'observation'...
  unless ( $obs_type eq 'observation' ) {
    $log->debug("Message not of type 'observation' - returning");
    return ESTAR__OK;
  }


  # START OF DATA PROCESSING ##############################################
  
  # THAW OBSERVATION
  # ================
  
  # thaw the observation object
  my $observation_object = eSTAR::Util::thaw( $id );
  return ESTAR__ERROR unless defined $observation_object;
  
  # stuff into object 
  $self->{OBS} = $observation_object;
  
  # PROCESS DATA
  # ============

  $log->print("Automatic Cross Correlation started...");
  my $header = $self->{OBS}->fits_header();
     
  # grab FITS headers
  my $FCRA = $header->itembyname( 'FCRA' );
  my $FCDEC = $header->itembyname( 'FCDEC' );
  my $XPS = $header->itembyname( 'XPS' );
  my $YPS = $header->itembyname( 'YPS' );
  unless ( defined $FCRA && defined $FCDEC && defined $XPS && defined $YPS ) {
     $log->warn( "Warning: FITS Header keywords not present" );
     $self->{OBS}->status("fits problem");                
     my $status = eSTAR::Util::freeze( $id, $self->{OBS} ); 
     if ( $status == ESTAR__ERROR ) {
        $log->warn( 
            "Warning: Problem re-serialising the \$self->{OBS}");
     }
     $log->error( "Error: Returning a 'ESTAR__ERROR'..." );
     return ESTAR__ERROR;    
  } 
  
  # RA & Dec         
  my $ra = $FCRA->value();
  my $dec = $FCDEC->value();
  $log->debug("Field Centre: $ra, $dec");
    
  # X-pixel scale   
  my $xscale = $XPS->value();
  $log->debug("X Plate Scale: $xscale arcsec/pixel");
  
  # Y-pixel scale   
  my $yscale = $YPS->value();
  $log->debug("Y Plate Scale: $yscale arcsec/pixel");
 
  # field radius
  my $radius = $config->get_option("usnoa2.radius"); 
  my $nout = $config->get_option("usnoa2.nout"); 
             
  # proxy
  my $proxy = $config->get_option("connection.proxy");
  $proxy = "" if $proxy eq "NONE";   
                       
  $log->debug("Querying ESO-ECF...");
                  
  # grab USNO-A2 catalogue 
  # ----------------------
  my $usno = new Astro::Catalog::Query::USNOA2( RA     => $ra,
                                                Dec    => $dec, 
                                                Proxy  => $proxy, 
                                                Radius => $radius, 
                                                Number => $nout );
             
  my $usnoa2_catalog = $usno->querydb();
  $log->debug( $usnoa2_catalog->sizeof() . " stars returned");
                         
  # write to file
  my @out_mags = ( 'R' );
  my @out_cols = ( 'B-R' );            
             
  # USNO-A2 reference.cat
  my $ref_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                       "$id.corlate_ref.cat");
  $log->debug("Writing reference catalogue to disk...");
  my $status = $usnoa2_catalog->write_catalog( Format     => 'Cluster',  
                                               File       => $ref_file,  
                                               Magnitudes => \@out_mags, 
                                               Colours    => \@out_cols);
   
  # grab OBJECT catalogue
  # ---------------------
  
  my $object_catalog = $self->{OBS}->catalog(); 

  #use Data::Dumper;
  #print "Object Catalogue:\n";
  #print "-----------------\n\n";
  #print Dumper( $object_catalog ) ."\n\n"; 
   
  # object catalogue
  my $obj_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                    "$id.corlate_obj.cat");
  $log->debug("Writing object catalogue to disk...");
  $status = $object_catalog->write_catalog( Format     => 'Cluster',  
                                            File       => $obj_file  );
                                    
                   
  # New CORLATE object
  # ------------------
   
  $log->debug("Building corelation object...");
  my $corlate = new Astro::Corlate(  Reference   => $ref_file,
                                     Observation => $obj_file  );
  
  # log file
  my $log_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                        "$id.corlate_log.log");
  $corlate->logfile( $log_file );

  # fit catalog
  my $fit_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                      "$id.corlate_fit.fit");
  $corlate->fit( $fit_file );
                   
  # histogram
  my $hist_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                       "$id.corlate_hist.dat");
  $corlate->histogram( $hist_file );
                   
  # information
  my $info_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                       "$id.corlate_info.dat");
  $corlate->information( $info_file );
                   
  # varaiable catalog
  my $var_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                      "$id.corlate_var.cat");
  $corlate->variables( $var_file );
                   
  # data catalog
  my $data_file = File::Spec->catfile( $config->get_tmp_dir(), 
                                       "$id.corlate_fit.cat");
  $corlate->data( $data_file);
                   
  # Astro::Corlate inputs
  # ---------------------
  my ($volume, $directories, $file); 
 
  $log->debug("Starting cross correlation...");
  ($volume, $directories, $file) = File::Spec->splitpath( $ref_file );
  $log->debug("Temporary directory   : " . $directories);
  $log->debug("Reference catalogue   : " . $file);
  
  ($volume, $directories, $file) = File::Spec->splitpath( $obj_file );
  $log->debug("Observation catalogue : " . $file);
  
  ($volume, $directories, $file) = File::Spec->splitpath( $log_file );
  $log->debug("Log file              : " . $file);
  
  ($volume, $directories, $file) = File::Spec->splitpath( $fit_file );
  $log->debug("X/Y Fit file          : " . $file);
  
  ($volume, $directories, $file) = File::Spec->splitpath( $hist_file );
  $log->debug("Histogram file        : " . $file);
  
  ($volume, $directories, $file) = File::Spec->splitpath( $info_file );
  $log->debug("Information file      : " . $file);
  
  ($volume, $directories, $file) = File::Spec->splitpath( $var_file );
  $log->debug("Variable catalogue    : " . $file);
  
  ($volume, $directories, $file) = File::Spec->splitpath( $data_file );
  $log->debug("Colour data catalogue : " . $file);
                              
                   
  # run the corelation routine
  # --------------------------
  my $status = ESTAR__OK;
  try {
     $log->debug("Called run_corlate()...");
     $corlate->run_corlate();
  } otherwise {
     my $error = shift;
     eSTAR::Error->flush if defined $error;
     $status = ESTAR__ERROR;
                
     # grab the error line
     my $err = "$error";
     chomp($err);
     $log->debug("Error: $err");
  }; 
  
  # undef the Astro::Corlate object
  $corlate = undef;
  
  # check for good status
  # ---------------------
  unless ( $status == ESTAR__OK ) {
     $log->warn( "Warning: Cross Correlation routine failed to run" );
     $self->{OBS}->status("corlate problem");                
     my $status = eSTAR::Util::freeze( $id, $self->{OBS} ); 
     if ( $status == ESTAR__ERROR ) {
        $log->warn( 
            "Warning: Problem re-serialising the \$self->{OBS}");
     }
     $log->error( "Error: Returning a 'ESTAR__ERROR'..." );
     return ESTAR__ERROR;    
  }   
   
  # stuff catalogs into observation object
  # --------------------------------------
  my $ref_cat = new Astro::Catalog( Format => 'Cluster',
                                    File   => $ref_file );
  unless ( defined $ref_cat ) {
     $log->warn( "Warning: Reference Catalogue not created");
  }        
  $self->{OBS}->reference_catalog( $ref_cat ); 
  $log->debug("Reference catalogue has " . $ref_cat->sizeof() . " stars");
                                      
  my $var_cat = new Astro::Catalog( Format => 'Cluster',
                                    File   => $var_file );
  unless ( defined $ref_cat ) {
     $log->warn( "Warning: Variable Star Catalogue not created");
  }        
  $self->{OBS}->variable_catalog( $var_cat );
  $log->debug("Variable catalogue has " . $var_cat->sizeof() . " stars");
                       
  my $col_cat = new Astro::Catalog( Format => 'Cluster',
                                    File   => $data_file );
  unless ( defined $ref_cat ) {
     $log->warn( "Warning: Colour Data Catalogue not created");
  }        
  $self->{OBS}->data_catalog( $col_cat ); 
  $log->debug("Colour catalogue has " . $col_cat->sizeof() . " stars");
                     
  # stuff remaining files into observation object
  # ---------------------------------------------
  my ($log_string, $fit_string );
  my ($hist_string, $info_string);
                     
  unless ( open ( FILE, "<$log_file" ) ) {
     $log->warn( "Warning: Can not open file $log_file");
  } else {
     undef $/;
     $log_string = <FILE>;
     close FILE; 
     $/ = "\n";
  }
  $self->{OBS}->corlate_log( $log_string );
                                
  unless ( open ( FILE, "<$fit_file" ) ) {
     $log->warn( "Warning: Can not open file $fit_file");
  } else {
     undef $/;
     $fit_string = <FILE>;
     close FILE; 
     $/ = "\n";
  }
  $self->{OBS}->corlate_fit( $fit_string );
                               
  unless ( open ( FILE, "<$hist_file" ) ) {
     $log->warn( "Warning: Can not open file $hist_file");
  } else {
     undef $/;
     $hist_string = <FILE>;
     close FILE; 
     $/ = "\n";
  }
  $self->{OBS}->corlate_hist( $hist_string );
                     
  unless ( open ( FILE, "<$info_file" ) ) {
     $log->warn( "Warning: Can not open file $info_file");
  } else {
     undef $/;
     $info_string = <FILE>;
     close FILE; 
     $/ = "\n";
  }
  $self->{OBS}->corlate_info( $info_string );
                               
  # Grab the number of variable stars in the field
  # ----------------------------------------------
  my $number_var = $var_cat->sizeof();
  if ( $number_var == 1 ) {
     $log->print("$number_var Variable Found"); 
  } elsif ( $number_var > 1 ) {
     $log->print("$number_var Variables Found"); 
  } else {
     $log->print("No Variables Found"); 
  }   
    
  # FREEZE OBSERVATION
  # ==================
  
  # freeze the observation object before calling the followup observations
  # giving us a better chance of getting it updated correctly if returned
  # followup obervations turn up while we are still creating new ones.
  my $status = eSTAR::Util::freeze( $id, $self->{OBS} ); 
  if ( $status == ESTAR__ERROR ) {
     $log->warn( 
         "Warning: Problem re-serialising the \$self->{OBS}");
     return ESTAR__ERROR;    
  } 

  
  # TIDY UP TMP DIRECTORY
  # =====================
  #my @file_list = ( $ref_file, $obj_file, $log_file, $fit_file, 
  #                  $hist_file,$info_file, $var_file, $data_file );
  #eval { unlink ( @file_list); };
  #if ( $@ ) {
  #   $log->warn("Warning: Can not unlink files in " .
  #                    $config->get_tmp_dir() );
     $log->warn("Warning: Not unlinking files in " .
                      $config->get_tmp_dir() );
  #}        
    
  # IF VARAIABLES > 0 THEN REQUEST AUTO OBSERVATIONS
  # ================================================
   
  # everything else has been tided up, now lets request followup observations
  # if needed. There may be a problem here for folloup() > 2 or 3 (or so) as
  # we may end up with blocked ports. This all might need to be threaded, and
  # I might have to look a further threading the node_agent if we do have
  # problems. Not good...          
  if ( $number_var > 0 ) { 
     
     # grab the observation message document, has to be there otherwise
     # we wouldn't be here...
     my $obs_document = $self->{OBS}->observation();

     # generate an observation request for each followup image required
     foreach my $j ( 1 ... $self->{OBS}->followup()) {
  
        $log->print("Creating followup observation #" . $j . "..." );
        
        my %observation;
        $observation{"user"} = $self->{OBS}->username();
        $observation{"pass"} = $self->{OBS}->password();
        $observation{"ra"} = $ra;     # use field centre RA
        $observation{"dec"} = $dec;   # use field centre Dec
        #$observation{"target"} = $obs_document->target();
        $observation{"exposure"} = $obs_document->exposure();
        $observation{"flux"} =  $obs_document->flux();
        $observation{"passband"} =  $self->{OBS}->passband();
        
        $observation{"type"} = "Automatic $id";

        # exposure _or_ (signaltonoise & flux) should be defined
        $observation{"flux"} =  $obs_document->flux();
        if ( defined $observation{"flux"} ) {
           $observation{"signaltonoise"} = $obs_document->snr();
        } else {
           # expsores are stored in milliseconds in RTML, but we pass them
           # in seconds, fiddle with the numbers so odd things don't happen
           $observation{"exposure"} = $obs_document->exposure();
           $observation{"exposure"} = $observation{"exposure"}/1000.0;
        }

        
        $log->debug("Calling new_observation... " );
        foreach my $key ( keys %observation ) {
           $log->debug("$key => " . $observation{$key});
        }

        # call the new_observation routine directly passing it a valid
        # username and password, only problem with this is that we get
        # a SOAP::Data object back that we don't really want.
        my $cookie = 
          eSTAR::Util::make_cookie($observation{"user"}, $observation{"pass"});
        my $handler = new eSTAR::UA::Handler( );
        $handler->set_user( user   => $observation{"user"},
                            cookie => $cookie );
        my $soap_data = $handler->new_observation( %observation ); 

        $log->print(
        "Returned control to eSTAR::UA::Algorithm::PhotometryFollowup object" );     
        
        # grab the string out of the returned SOAP::Data object, this isn't
        # particularly nice thing to have to do, and I'm not convinced its
        # going to work in every case, but may as well have a bash at it.
        my $soap_value = ${${$soap_data}{'_value'}}[0];
        $log->debug("Got a '" . $soap_value . "' message");
                
     }
  }      
 
  # END OF DATA PROCESSING ################################################
                            
  return ESTAR__OK;
}

              
1;
