package eSTAR::ADP::Util;

=head1 NAME

eSTAR::ADP::Util - Miscellaneous useful routines for implementing a virtual
telescope network.


=over 4

=cut


use strict;
use warnings;

use threads;
use threads::shared;
use Thread::Semaphore;

use eSTAR::Logging;
use eSTAR::Constants qw( :status ); 
use eSTAR::Process;

use Sys::Hostname;
use IO::Socket::INET;
use DateTime;
use DateTime::Duration;
use DateTime::Format::ISO8601;
use DateTime::Format::Epoch;

require Exporter;
use vars qw( $VERSION @EXPORT_OK %EXPORT_TAGS @ISA );

@ISA = qw( Exporter );
@EXPORT_OK = qw( 
                  get_network_time
                  str2datetime
                  get_first_datetime
                  datetime_strs2theorytimes
                  theorytime2datetime
                  datetime2utc_str
                  init_logging
                  read_n_column_file
                  build_dummy_header
                );


%EXPORT_TAGS = ( 
                  'all' => [ qw(
                                 get_network_time
                                 str2datetime
                                 get_first_datetime
                                 datetime_strs2theorytimes
                                 theorytime2datetime
                                 datetime2utc_str
                                 init_logging
                                 read_n_column_file
                                 build_dummy_header
                                )                                                      
                           ],
                 );




=item B<get_network_time>

Queries a remote time server to discover what time it is. Host and port may be
optionally specified.

   $time = get_network_time([$host], [$port]);

=cut
{
my $cached_real_time;
my $cached_sim_time;
share($cached_real_time);
share($cached_sim_time);
my $semaphore = new Thread::Semaphore;

sub get_network_time {
   my $host = shift || 'localhost';
   my $port = shift || 6667;

   # Interval between time server refreshes, in seconds...
   my $caching_interval = new DateTime::Duration( seconds => 1.0);
         
   $semaphore->down;
   my $current_real_time = DateTime->now;
   if ( $cached_real_time ) {
        if (($current_real_time - $caching_interval) < str2datetime($cached_real_time) ) {
            $semaphore->up;
            return str2datetime($cached_sim_time);
      }
   }

   print "****Cache has expired - querying time server****\n";

   my $socket = IO::Socket::INET->new("$host:$port")
      or die "Couldn't establish connection to time server: $@";

   my $time_str;
   while ( <$socket> ) {
      $time_str = $_;
   }


   my $dt = str2datetime($time_str);

   $cached_sim_time = "$dt";
   $cached_real_time = "$current_real_time";
   
   $semaphore->up;
   
   return $dt;
}
}

=item B<str2datetime>

Wraps DateTime::Format::ISO8601->parse_datetime to ensure the time zone is
correctly set to UTC.

=cut
sub str2datetime {
   my $time_string = shift;   

   # Grab the required time adjustments....   
   my ($direction, $hrs, $mins) = $time_string =~ m/([+-])(\d{2})(\d{2})$/;

   # Remove the non-supported '+0000' tail indicating UTC offset
   $time_string =~ s/[+-]\d{4}$//;


   # Turn the stringified time back into a dateTime object...
   my $dt = DateTime::Format::ISO8601->parse_datetime( $time_string );
   

   # Set defaults in case there is no time string...
   $direction = '+'  unless defined $direction;
   $hrs       = '00' unless defined $hrs;
   $mins      = '00' unless defined $mins;

   # Apply the offset to UTC. Let DateTime handle this...
   my $offset = DateTime::Duration->new( hours => $hrs, minutes => $mins);
   if ( $direction eq '-' ) {
      $dt = $dt - $offset;
   }
   else {
      $dt = $dt + $offset;
   }


   # The parser sets the timezone to 'floating', not UTC. So we fix this...
   $dt->set_time_zone('UTC');

   return $dt;
}



# Find the earliest datetime in an array of datetimes...
sub get_first_datetime {      
   my $first = DateTime->new(year=>3000);

   while ( @_ ) {
      my $datetime_str = shift;

      # Convert string to datetime object...
      my $datetime = str2datetime($datetime_str);
      $first = $datetime if $datetime < $first;
   }

   return $first;
}

sub datetime_strs2theorytimes {
   my $first     = shift;
   my $runlength = shift;
   my @dt_strs   = @_;

   
   my $formatter = DateTime::Format::Epoch->new(
                       epoch          => $first,
                       unit           => 'seconds',
                       type           => 'int',    # or 'float', 'bigint'
                       skip_leap_seconds => 1,
                       start_at       => 0,
                       local_epoch    => undef,
                   );

   # Using epochs means month boundaries are handled correctly...
   my $end_datetime = $first + $runlength;
   my $rl_in_secs = $formatter->format_datetime($end_datetime);

   # Translate all datetimes using the first as a reference point...
   my @tts;
   foreach my $datetime_str ( @dt_strs ) {
      my $datetime = str2datetime($datetime_str);
      
      my $epoch_time = $formatter->format_datetime($datetime);
      
      
      my $theorytime = $epoch_time / $rl_in_secs;
      
      push @tts, $theorytime;
   }
   @tts = sort { $a <=> $b } @tts;

   return @tts;
}

# THIS FUNCTION IS DEPRECATED. IT DOES NOT WORK FOR ACTUAL RUNS EXCEEDING ONE
# MONTH! DELETE THIS AFTER THE ADP TEST RUN IS COMPLETE (I.E. AFTER 09/07)!!
# USE THE EPOCH VERSION INSTEAD!!!
sub datetime_strs2theorytimes_old {
   my $first     = shift;
   my $runlength = shift;
   my @dt_strs   = @_;


   # Translate all datetimes using the first as a reference point...
   my @tts;
   foreach my $datetime_str ( @dt_strs ) {
      my $datetime = str2datetime($datetime_str);
      my $interval = ( $datetime - $first );
      
      
      # We have to do this crap because DateTime::Duration refuses to convert
      # between hours and secs etc. because of leap issues. But we don't care.
      my $int_in_secs   = $interval->delta_days * 24 * 3600 
                          + $interval->delta_minutes * 60 
                          + $interval->delta_seconds;
      
      my $rl_in_secs = $runlength->delta_days * 24 * 3600
                       + $runlength->delta_minutes * 60
                       + $runlength->delta_seconds;
      
      my $theorytime = $int_in_secs / $rl_in_secs;
      
      push @tts, $theorytime;
   }
   @tts = sort { $a <=> $b } @tts;

   return @tts;
}



sub theorytime2datetime {
   my $theorytime = shift;
   my $first = shift;
   my $runlength = shift;

   my $duration = $theorytime * $runlength;

   my $datetime = $first + $duration;

   return $datetime;
}


=item B<utc_datetime2str>

Return a stringified version of the datetime object with +0000 appended to the
end. This assumes that the datetime is actually in UTC...

=cut
sub datetime2utc_str {
   my $datetime = shift;
   my $str;

   # Don't append anything if there's already something appended...
   $str = $datetime =~ m/[+-]\d{4}$/ ? "$datetime" : "$datetime+0000";
   
   return $str; 
}


=item B<init_logging>

Starts the logging system. Defaults to full debug info unless $debug_toggle is 
specified as 'ESTAR__QUIET'.

   $log_object = init_logging($verbose_name, $version, [$debug_toggle]);

=cut
sub init_logging {
   my $verbose_name = shift;
   my $version      = shift;
   my $log_toggle   = shift || ESTAR__DEBUG;  # ESTAR__QUIET or ESTAR__DEBUG...

   # Identify process - determines where log and status files will be stored...
   my ($process_name) = $0 =~ m{.*/(.*)[.]pl};
   my $process = new eSTAR::Process( $process_name );  

   # Turn off buffering...
   $| = 1;

   # Get date and time...
   my $date = localtime;
   my $host = hostname;

   # start the log system
   my $log = new eSTAR::Logging( $process->get_process );

   # Toggle logging verbosity...
   $log->set_debug($log_toggle);

   # Start of log file...
   $log->header("Starting $verbose_name: Version $version");
   $process->set_version( $version );
   
   return $log;
}


=item B<read_n_column_file>

   Reads in a text table with any number of columns, returning the data as a
   list of column (list) references.
   
   @data = read_n_column_file($filename);

=cut
sub read_n_column_file {
   my $filename = shift;
   my @columns;

   open my $read_fh, '<', $filename or die "Can't open $filename to read: $!";

   # Read in a line...
   while ( <$read_fh> ) {
      # Skip commented out or blank lines...
      next if ( /^#|^$/ );                     
     
      
      # Split input line on spaces, and consider each element of that line...
      my $n_col = 0;
      foreach my $element ( split ) {
        # Remove any leading/trailing whitespace... 
        $element =~ s/^\s+//;    
        $element =~ s/\s+$//;
        
        # Append the element to the appropriate column array...
        push @{$columns[$n_col]}, $element;
        $n_col++;
      }
   }

   close $read_fh;
   
   return @columns;
}


=item B<build_dummy_header>

Returns an accurate example of a FITS header as one huge string. The 'DATE-OBS'
field is filled with the supplied time.

   $header_string = build_dummy_header($timestamp);

=cut
sub build_dummy_header {
   my $timestamp = shift;

   my $header = 
"SIMPLE  =                    T / A valid FITS file                              
BITPIX  =                   16 / Comment                                        
NAXIS   =                    2 / Number of axes                                 
NAXIS1  =                 1024 / Comment                                        
NAXIS2  =                 1024 / Comment                                        
BZERO   =         8.502683E+03 / Comment                                        
BSCALE  =         2.245839E-01 / Comment                                        
ORIGIN  = 'Liverpool JMU'                                                       
OBSTYPE = 'EXPOSE  '           / What type of observation has been taken        
RUNNUM  =                   34 / Number of Multrun                              
EXPNUM  =                    1 / Number of exposure within Multrun              
EXPTOTAL=                    2 / Total number of exposures within Multrun       
DATE    = '2006-10-03'         / [UTC] The start date of the observation        
DATE-OBS= '*****' / [UTC] The start time of the observation   
UTSTART = '20:03:59.229'       / [UTC] The start time of the observation        
MJD     =         54011.836102 / [days] Modified Julian Days.                   
EXPTIME =           99.5000000 / [Seconds] Exposure length.                     
FILTER1 = 'SDSS-R  '           / The first filter wheel filter type.            
FILTERI1= 'SDSS-R-01'          / The first filter wheel filter id.              
FILTER2 = 'clear   '           / The second filter wheel filter type.           
FILTERI2= 'Clear-01'           / The second filter wheel filter id.             
INSTRUME= 'RATCam  '           / Instrument used.                               
INSTATUS= 'Nominal '           / The instrument status.                         
CONFIGID=                56110 / Unique configuration ID.                       
CONFNAME= 'RATCam-SDSS-R-2'    / The instrument configuration used.             
DETECTOR= 'EEV CCD42-40 7041-10-5' / Science grade (1) chip.                    
PRESCAN =                   28 / [pixels] Number of pixels in left bias strip.  
POSTSCAN=                   28 / [pixels] Number of pixels in right bias strip. 
GAIN    =            2.7960000 / [electrons/count] calibrated leach 30/01/2000 1
READNOIS=            7.0000000 / [electrons/pixel] RJS 23/10/2004 (from bias)   
EPERDN  =            2.7960000 / [electrons/count] leach 30/01/2000 14:19.      
CCDXIMSI=                 1024 / [pixels] Imaging pixels                        
CCDYIMSI=                 1024 / [pixels] Imaging pixels                        
CCDXBIN =                    2 / [pixels] X binning factor                      
CCDYBIN =                    2 / [pixels] Y binning factor                      
CCDXPIXE=            0.0000135 / [m] Size of pixels, in X:13.5um                
CCDYPIXE=            0.0000135 / [m] Size of pixels, in Y:13.5um                
CCDSCALE=            0.2783700 / [arcsec/binned pixel] Scale of binned image on 
CCDRDOUT= 'LEFT    '           / Readout circuit used.                          
CCDSTEMP=                  166 / [Kelvin] Required temperature.                 
CCDATEMP=                  166 / [Kelvin] Actual temperature.                   
CCDWMODE=                    F / Using windows if TRUE, full image if FALSE     
CCDWXOFF=                    0 / [pixels] Offset of window in X, from the top co
CCDWYOFF=                    0 / [pixels] Offset of window in Y, from the top co
CCDWXSIZ=                 1024 / [pixels] Size of window in X.                  
CCDWYSIZ=                 1024 / [pixels] Size of window in Y.                  
CALBEFOR=                    F / Whether the calibrate before flag was set      
CALAFTER=                    F / Whether the calibrate after flag was set       
ROTCENTX=                  643 / [pixels] The rotator centre on the CCD, X pixel
ROTCENTY=                  393 / [pixels] The rotator centre on the CCD, Y pixel
TELESCOP= 'Liverpool Telescope' / The Name of the Telescope                     
TELMODE = 'ROBOTIC '           / [{PLANETARIUM, ROBOTIC, MANUAL, ENGINEERING}] T
TAGID   = 'PATT    '           / Telescope Allocation Committee ID              
USERID  = 'keith.horne'        / User login ID                                  
PROPID  = 'PL04B17 '           / Proposal ID                                    
GROUPID = '001518:UA:v1-24:run#10:user#aa' / Group Id                           
OBSID   = 'ExoPlanetMonitor'   / Observation Id                                 
GRPTIMNG= 'MONITOR '           / Group timing constraint class                  
GRPUID  =                24377 / Group unique ID                                
GRPMONP =         1200.0000000 / [secs] Group monitor period                    
GRPNUMOB=                    1 / Number of observations in group                
GRPEDATE= '2006-10-04 T 07:00:05 UTC' / [date] Group expiry date                
GRPNOMEX=          229.0000000 / [secs] Group nominal exec time                 
GRPLUNCO= 'BRIGHT  '           / Maximum lunar brightness                       
GRPSEECO= 'POOR    '           / Minimum seeing                                 
COMPRESS= 'PROFESSIONAL'       / [{PLANETARIUM, PROFESSIONAL, AMATEUR}] Compress
LATITUDE=           28.7624000 / [degrees] Observatory Latitude                 
LONGITUD=          -17.8792000 / [degrees West] Observatory Longitude           
RA      = ' 18:4:4.04'         / [HH:MM:SS.ss] Currently same as CAT_RA         
DEC     = '-28:38:38.70'       / [DD:MM:SS.ss] Currently same as CAT_DEC        
RADECSYS= 'FK5     '           / [{FK4, FK5}] Fundamental coordinate system of c
LST     = ' 19:41:55.00'       / [HH:MM:SS] Local sidereal time at start of curr
EQUINOX =         2000.0000000 / [Years] Date of the coordinate system for curre
CAT-RA  = ' 18:4:4.04'         / [HH:MM:SS.sss] Catalog RA of the current observ
CAT-DEC = '-28:38:38.70'       / [DD:MM:SS.sss] Catalog declination of the curre
CAT-EQUI=         2000.0000000 / [Year] Catalog date of the coordinate system fo
CAT-EPOC=         2000.0000000 / [Year] Catalog date of the epoch               
CAT-NAME= 'OB06251 '           / Catalog name of the current observation source 
OBJECT  = 'OB06251 '           / Actual name of the current observation source  
SRCTYPE = 'EXTRASOLAR'         / [{EXTRASOLAR, MAJORPLANET, MINORPLANET, COMET,]
PM-RA   =            0.0000000 / [sec/year] Proper motion in RA of the current o
PM-DEC  =            0.0000000 / [arcsec/year] Proper motion in declination  of 
PARALLAX=            0.0000000 / [arcsec] Parallax of the current observation so
RADVEL  =            0.0000000 / [km/s] Radial velocity of the current observati
RATRACK =            0.0000000 / [arcsec/sec] Non-sidereal tracking in RA of the
DECTRACK=            0.0000000 / [arcsec/sec] Non-sidereal tracking in declinati
TELSTAT = 'WARN    '           / [---] Current telescope status                 
NETSTATE= 'ENABLED '           / Network control state                          
ENGSTATE= 'DISABLED'           / Engineering override state                     
TCSSTATE= 'OKAY    '           / TCS state                                      
PWRESTRT=                    F / Power will be cycled imminently                
PWSHUTDN=                    F / Power will be shutdown imminently              
AZDMD   =          207.7049000 / [degrees] Azimuth demand                       
AZIMUTH =          207.7045000 / [degrees] Azimuth axis position                
AZSTAT  = 'TRACKING'           / Azimuth axis state                             
ALTDMD  =           28.3936000 / [degrees] Altitude axis demand                 
ALTITUDE=           28.3937000 / [degrees] Altitude axis position               
ALTSTAT = 'TRACKING'           / Altitude axis state                            
AIRMASS =            2.1200000 / [n/a] Airmass                                  
ROTDMD  =           43.8711000 / Rotator axis demand                            
ROTMODE = 'SKY     '           / [{SKY, MOUNT, VFLOAT, VERTICAL, FLOAT}] Cassegr
ROTSKYPA=            0.0000000 / [degrees] Rotator position angle               
ROTANGLE=           43.8715000 / [degrees] Rotator mount angle                  
ROTSTATE= 'TRACKING'           / Rotator axis state                             
ENC1DMD = 'OPEN    '           / Enc 1 demand                                   
ENC1POS = 'OPEN    '           / Enc 1 position                                 
ENC1STAT= 'IN POSN '           / Enc 1 state                                    
ENC2DMD = 'OPEN    '           / Enc 2 demand                                   
ENC2POS = 'OPEN    '           / Enc 2 position                                 
ENC2STAT= 'IN POSN '           / Enc 2 state                                    
FOLDDMD = 'PORT 3  '           / Fold mirror demand                             
FOLDPOS = 'PORT 3  '           / Fold mirror position                           
FOLDSTAT= 'OFF-LINE'           / Fold mirror state                              
PMCDMD  = 'OPEN    '           / Primary mirror cover demand                    
PMCPOS  = 'OPEN    '           / Primary mirror cover position                  
PMCSTAT = 'IN POSN '           / Primary mirror cover state                     
FOCDMD  =           27.3300000 / [mm] Focus demand                              
TELFOCUS=           27.3300000 / [mm] Focus position                            
DFOCUS  =            0.0000000 / [mm] Focus offset                              
FOCSTAT = 'WARNING '           / Focus state                                    
MIRSYSST= 'UNKNOWN '           / Primary mirror support state                   
WMSHUMID=           34.0000000 / [0.00% - 100.00%] Current percentage humidity  
WMSTEMP =          289.1500000 / [Kelvin] Current (external) temperature        
WMSPRES =          782.0000000 / [mbar] Current pressure                        
WINDSPEE=            4.7000000 / [m/s] Windspeed                                
WINDDIR =          119.0000000 / [degrees E of N] Wind direction                
TEMPTUBE=           15.6600000 / [degrees C] Temperature of the telescope tube  
WMSSTATE= 'OKAY    '           / WMS system state                               
WMSRAIN = 'SET     '           / Rain alert                                     
WMSMOIST=            0.0400000 / Moisture level                                 
WMOILTMP=           11.6000000 / Oil temperature                                
WMSPMT  =            0.0000000 / Primary mirror temperature                     
WMFOCTMP=            0.0000000 / Focus temperature                              
WMAGBTMP=            0.0000000 / AG Box temperature                             
WMSDEWPT=            0.3000000 / Dewpoint                                       
REFPRES =          770.0000000 / [mbar] Pressure used in refraction calculation 
REFTEMP =          283.1500000 / [Kelvin] Temperature used in refraction calcula
REFHUMID=           30.0000000 / [0.00% - 100.00%] Percentage humidity used in r
AUTOGUID= 'UNLOCKED'           / [{LOCKED, UNLOCKED SUSPENDED}] Autoguider lock 
AGSTATE = 'OKAY    '           / Autoguider sw state                            
AGMODE  = 'UNKNOWN '           / Autoguider mode                                
AGGMAG  =            0.0000000 / [mag] Autoguider guide star mag                
AGFWHM  =            0.0000000 / [arcsec] Autoguider FWHM                       
AGMIRDMD=            0.0000000 / [mm] Autoguider mirror demand                  
AGMIRPOS=            0.0000000 / [mm] Autoguider mirror position                
AGMIRST = 'WARNING '           / Autoguider mirror state                        
AGFOCDMD=            2.7990000 / [mm] Autoguider focus demand                   
AGFOCUS =            2.7980000 / [mm] Autoguider focus position                 
AGFOCST = 'WARNING '           / Autoguider focus state                         
AGFILDMD= 'UNKNOWN '           / Autoguider filter demand                       
AGFILPOS= 'UNKNOWN '           / Autoguider filter position                     
AGFILST = 'WARNING '           / Autoguider filter state                        
MOONSTAT= 'UP      '           / [{UP, DOWN}] Moon position at start of current 
MOONFRAC=            0.8468916 / [(0 - 1)] Lunar illuminated fraction           
MOONDIST=           53.3774525 / [(degs)] Lunar Distance from Target            
MOONALT =           34.7596645 / [(degs)] Lunar altitude                        
SCHEDSEE=            2.0858450 / [(arcsec)] Predicted seeing when group schedule
SCHEDPHT=            1.0000000 / [(0-1)] Predicted photom when group scheduled  
ESTSEE  =            3.3316001 / [(arcsec)] Estimated seeing at start of observa
L1MEDIAN=         7.023166E+03 / [counts] median of frame background in counts  
L1MEAN  =         7.021803E+03 / [counts] mean of frame background in counts    
L1STATOV=                   23 / Status flag for DP(RT) overscan correction     
L1STATZE=                   -1 / Status flag for DP(RT) bias frame (zero) correc
L1STATZM=                    1 / Status flag for DP(RT) bias frame subtraction m
L1STATDA=                   -1 / Status flag for DP(RT) dark frame correction   
L1STATTR=                    1 / Status flag for DP(RT) overscan trimming       
L1STATFL=                    1 / Status flag for DP(RT) flatfield correction    
L1XPIX  =         4.776160E+02 / Coordinate of brightest object in frame after t
L1YPIX  =         0.000000E+00 / Coordinate of brightest object in frame after t
L1COUNTS=         9.887205E+04 / [counts] Counts in brightest object (sky subtra
L1SKYBRT=         9.990000E+01 / [mag/arcsec^2] Estimated sky brightness        
L1PHOTOM=        -9.990000E+02 / [mag] Estimated extinction for standards images
L1SAT   =                    F / [logical] TRUE if brightest object is saturated
BACKGRD =         7.023166E+03 / [counts] frame background level in counts      
STDDEV  =         1.982379E+02 / [counts] Standard deviation of Backgrd in count
L1SEEING=         9.990000E+02 / [Dummy] Unable to calculate                    
SEEING  =         9.990000E+02 / [Dummy] Unable to calculate                    ";

   # Insert the timestamp into the FITS header, if one was provided...
   $header =~ s/[*]{5}/$timestamp/ if $timestamp;

   return $header;
}

=back

=head1 COPYRIGHT

Copyright (C) 2007 University of Exeter. All Rights Reserved.


=head1 AUTHORS

Eric Saunders E<lt>saunders@astro.ex.ac.ukE<gt>

=cut

1;
