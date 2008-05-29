#!/software/perl-5.8.8/bin/perl

use Time::localtime;
use Data::Dumper;
use Astro::VO::VOEvent;
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;

my $event_host = "estar6.astro.ex.ac.uk";
my $event_port = "9099";

my $agent_host = "estar5.astro.ex.ac.uk";
my $agent_port = "8000";

# create a user/passwd cookie
my $cookie = make_cookie( "agent", "InterProcessCommunication" );

# G R A B   K E Y W O R D S ---------------------------------------------------

my $string = $ENV{QUERY_STRING};
my @pairs = split( /&/, $string );

# loop through the query string passed to the script and seperate key
# value pairs, remembering to un-Webify the munged data
my %query;
foreach my $i ( 0 ... $#pairs ) {
   my ( $name, $value ) = split( /=/, $pairs[$i] );

   # Un-Webify plus signs and %-encoding
   $value =~ tr/+/ /;
   $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
   $value =~ s/<!--(.|\n)*-->//g;
   $value =~ s/<([^>]|\n)*>//g;

   $query{$name} = $value;
}

# G E N E R A T E   O B S E R V A T I O N ------------------------------------

my %observation;
$observation{user} = "kdh1";
$observation{pass} = "EXOfollowup";
$observation{project} = "exoplanet";
$observation{ra} = $query{ra};
$observation{dec} = $query{dec};
$observation{target} = $query{object_name};
$observation{exposure} = $query{exposure},
$observation{passband} = "R";
$observation{type} = "ExoPlanetMonitor";
$observation{groupcount} = $query{group_count};
$observation{starttime} = $query{start_time};
$observation{endtime} = $query{end_time};
$observation{toop} = $query{type};
$observation{filter} = $query{filter};
$observation{priority} = 0;

if( $observation{toop} eq "toop" ) {
  $observation{seriescount} = undef;
  $observation{interval} = undef;
  $observation{tolerance} = undef;
} else { 
  $observation{seriescount} = $query{series_count} if $query{series_count} ne "";
  $observation{interval} = "PT" . $query{interval} . "S" if $query{interval} ne "";
  $observation{tolerance} = "PT" . $query{tolerance} . "S" if  $query{tolerance} ne "";
}

# O B S E R V I N G   R E Q U E S T -------------------------------------------- 

# end point
my $agent_endpoint = "http://" . $agent_host . ":" . $agent_port;
my $agent_uri = new URI($agent_endpoint);

my $agent_cookie_jar = HTTP::Cookies->new();
$agent_cookie_jar->set_cookie(0, user => $cookie, '/', $agent_uri->host(), $agent_uri->port());

# create SOAP connection
my $agent_soap = new SOAP::Lite();

$agent_soap->uri( "urn:/user_agent" ); 
$agent_soap->proxy($agent_endpoint, cookie_jar => $agent_cookie_jar);
  
# report
  
# grab result 
my $obs_result;
if ( $query{"all_telescopes"} == 1 ) {
   eval { $obs_result = $agent_soap->all_telescopes( %observation ); };
} else {
   eval { $obs_result = $agent_soap->new_observation( %observation ); };
}
if ( $@ ) {
   my $error = "$@";
   error( $error );
   exit;   
}



my $obs_return = $obs_result->result(); 

# G E N E R A T E   P A G E --------------------------------------------------

print "Content-type: text/html\n\n";

print "<H2>Observation Status</H2>";
 
print "<fieldset>";
print "<div class='row'>";
print "<label>Transport</label>";
if ( $agent_soap->transport()->status() =~ "200" ) {
   print "<p id='green'>" . $agent_soap->transport()->status() . "</p>";
} else {
   print "<p id='red'>" . $agent_soap->transport()->status() . "</p>";
}
print "</div>";
if ($obs_result->fault() ) {
  print "<div class='row'>";
  print "<label>Fault</label>";
  print "<p>" . $obs_result->faultcode() . "</p>";
  print "</div>";
  print "<div>";
  print "<p>" . $obs_result->faultstring() . "</p>";
  print "</div>"; 
  print "</fieldset>";
  exit;
}
print "</fieldset>";

$obs_return =~ s/>/&gt;/g;
$obs_return =~ s/</&lt;/g;

print "<fieldset>";
my %telescopes;
if ( $obs_return =~ "OK" ) {
   my $string =~ m/\[($\w+)\]/;
   my @tels = split " ", $1;
   foreach my $i ( 0 ... $#tels ) {
      $telescopes{$tels[$i]} = 1;
   }   
} 
   
print "<div clas='row'>";
print "<label>LT</label>";
if ( $telescopes{LT} ) {
   print "<p id='green'>OK</p>";
} else {   
   print "<p id='red'>NO</p>";
}   
print "</div>"; 

print "<div clas='row'>";
print "<label>FTN</label>";
if ( $telescopes{FTN} ) {
   print "<p id='green'>OK</p>";
} else {   
   print "<p id='red'>NO</p>";
}   
print "</div>"; 

print "<div clas='row'>";
print "<label>FTS</label>";
if ( $telescopes{FTS} ) {
   print "<p id='green'>OK</p>";
} else {   
   print "<p id='red'>NO</p>";
}   
print "</div>";   
  
  
print "</fieldset>";
   
exit;

# S U B - R O U T I N E S ----------------------------------------------------

sub timestamp {
   # ISO format 2006-01-05T08:00:00
   		     
   my $year = 1900 + localtime->year();
   
   my $month = localtime->mon() + 1;
   $month = "0$month" if $month < 10;
   
   my $day = localtime->mday();
   $day = "0$day" if $day < 10;
   
   my $hour = localtime->hour();
   $hour = "0$hour" if $hour < 10;
   
   my $min = localtime->min();
   $min = "0$min" if $min < 10;
   
   my $sec = localtime->sec();
   $sec = "0$sec" if $sec < 10;
   
   my $timestamp = $year ."-". $month ."-". $day ."T". 
   		   $hour .":". $min .":". $sec;

   return $timestamp;
}

sub convert_from_sextuplets {
 my $ra = shift;
 my $dec = shift;
 
 my ($ra_hour, $ra_min, $ra_sec) = split " ", $ra;
 my ($dec_deg, $dec_min, $dec_sec) = split " ",$dec;
 $dec_deg =~ s/\+// if $dec_deg eq "+";

 my $decimal_ra = $ra_hour*15.0 + ($ra_min/60.0) + ($ra_sec/3600.0);
 
 my $decimal_dec;
 if ( $dec_deg =~ "-" ) {
    $decimal_dec = $dec_deg - ($dec_min/60.0) - ($dec_sec/3600.0);
 } else {   
    $decimal_dec = $dec_deg + ($dec_min/60.0) + ($dec_sec/3600.0);
 }
 
 return( $decimal_ra, $decimal_dec );
} 

sub make_cookie {
   my ($user, $passwd) = @_;
   my $cookie = $user . "::" . md5_hex($passwd);
   $cookie =~ s/(.)/sprintf("%%%02x", ord($1))/ge;
   $cookie =~ s/%/%25/g;
   $cookie;
}

sub grab_url_of_document {
   my $result = shift;
   
   my $param;
   if ( $result =~ "/home/estar/.estar/" ) {
      my @array = split "\n", $result;
      foreach my $i ( 0 ... $#array ) {
        if ( $array[$i] =~ "/home/estar/.estar/" ) {
           $param = $array[$i];
	   last;
        }
      }
   }

   my $start_index = rindex $param, 'value="';
   my $path = substr $param, $start_index+7;
   my $length = length $path;
   $path = substr $path, 0, $length-4;
   $path =~ s/\/home\/estar\/\.estar\/event_broker\/state\//http:\/\/www\.estar\.org\.uk\/voevent\//;

   return $path;
}


sub error {
   my $string = shift;
   
   print "Content-type: text/html\n\n";
   print "<p>" . $string . "</p>";
}   
