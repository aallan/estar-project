#!/software/perl-5.8.6/bin/perl

use Time::localtime;
use Data::Dumper;
use Astro::VO::VOEvent;
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;

my $event_host = "estar3.astro.ex.ac.uk";
my $event_port = "9099";

my $agent_host = "estar3.astro.ex.ac.uk";
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

# G R A B   F I L E S ---------------------------------------------------------

my $header;
unless ( open ( FILE, "<../header.inc") ) {
   error( "Can not open header.inc file", undef, \%query );
   exit;	
}
{
   undef $/;
   $header = <FILE>;
   close FILE;
}
$header =~ s/PAGE_TITLE_STRING/PLANET Override/g;

my $footer;
unless ( open ( FILE, "<../footer.inc") ) {
   error( "Can not open footer.inc file", undef, \%query );
   exit;	
}
{
   undef $/;
   $footer = <FILE>;
   close FILE;
}
$footer =~ s/LAST_MODIFIED_DATE/ctime()/e;

# G E N E R A T E   V O E V E N T --------------------------------------------

my $user = $ENV{REMOTE_USER};
my $author_ivorn = "ivo://uk.org.estar";
my $ivorn;
if ( $user eq "aa" ) {
   $ivorn = $author_ivorn . "/estar.ex#";
} elsif ( $user eq "rrw" ) {
   $ivorn = $author_ivorn . "/talons.lanl#";   
} else {
   $ivorn = $author_ivorn . "#";
}
$ivorn = $ivorn . "manual/" .lc($query{project}) ."/";
if ( $query{object_name} ne "" ) {
  $ivorn = $ivorn . $query{object_name} . "/";
  $ivorn =~ s/\s+/-/g;
}  
$ivorn = $ivorn . timestamp();

my %event;
$event{ID} = $ivorn;
$event{Role} = "observation";
if ( $query{description} ne "" ) {
  $event{Description} = $query{description}
}
$event{Who} = { Publisher => $author_ivorn . "#",
                      Date      => timestamp(),
                      Contact   => { Name        => $query{name},
                                     Institution => $query{project},
                                     Email       => $query{email} } };
				     
my ( $ra, $dec );
if ( $query{ra} ne "" && $query{dec} ne "" ) {				       
  ($ra, $dec) = convert_from_sextuplets( $query{ra}, $query{dec} );
  $event{WhereWhen} = { RA => $ra, 
                              Dec => $dec, 
                              Time => timestamp()
			    };  
}			          

if ( $query{concept} eq "EXO" && $query{object_name} ne "" ) {
 $event{Why} = [ { Inference => { Probability  => $query{probability},
                                  Relation     => "identified",
                                  Name         => $query{object_name},
                                  Concept      => "event.microlens;" } } ];
}
 
my $object = new Astro::VO::VOEvent( );
my $voevent = $object->build( %event );

# G E N E R A T E   O B S E R V A T I O N ------------------------------------

my %observation;
$observation{user} = "kdh1";
$observation{pass} = "EXOfollowup";
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

if( $observation{toop} eq "toop" ) {
  $observation{seriescount} = undef;
  $observation{interval} = undef;
  $observation{tolerance} = undef;
} else { 
  $observation{seriescount} = $query{series_count} if $query{series_count} ne "";
  $observation{interval} = "PT" . $query{interval} . "S" if $query{interval} ne "";
  $observation{tolerance} = "PT" . $query{tolerance} . "S" if  $query{tolerance} ne "";
}

# S U B M I T   E V E N T   M E S S A G E ------------------------------------

# end point
my $broker_endpoint = "http://" . $event_host . ":" . $event_port;
my $broker_uri = new URI($broker_endpoint);

my $broker_cookie_jar = HTTP::Cookies->new();
$broker_cookie_jar->set_cookie(0, user => $cookie, '/', $broker_uri->host(), $broker_uri->port());

# create SOAP connection
my $broker_soap = new SOAP::Lite();

$broker_soap->uri( "urn:/event_broker" ); 
$broker_soap->proxy($broker_endpoint, cookie_jar => $broker_cookie_jar);
  
# report
  
# grab result 
my $event_result;
eval { $event_result = $broker_soap->handle_voevent( $query{project}, $voevent ); };
if ( $@ ) {
   my $error = "$@";
   error( $error, \%event, \%query, $voevent );
   exit;   
}

if ($event_result->fault() ) {
  error( "(" . $event_result->faultcode() . "): " . $event_result->faultstring(), \%event, \%query, $voevent  );
  exit;
}  

# O B S E R V I N G   R E Q U E S T -------------------------------------------- 

# end point
my $agent_endpoint = "http://" . $agent_host . ":" . $agent_port;
my $agent_uri = new URI($agent_endpoint);

my $cookie2 = make_cookie( "agent", "xxx" );
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
   error( $error, \%observation, \%query );
   exit;   
}

if ($obs_result->fault() ) {
  error( "(" . $obs_result->faultcode() . "): " . $obs_result->faultstring(), \%observation, \%query  );
  exit;
}

# G E N E R A T E   P A G E --------------------------------------------------

print "Content-type: text/html\n\n";
print $header;

#print "<P>User = ".$ENV{REMOTE_USER}."</P>\n";
#foreach my $key ( sort keys %query ) {
#   print "$key = $query{$key}<BR>\n";
#}
#print "<P><PRE>" . Dumper( %observation ) . "</PRE></P>";

my $vo_return = $event_result->result();
my $path = grab_url_of_document( $vo_return );
$vo_return =~ s/>/&gt;/g;
$vo_return =~ s/</&lt;/g;
print "<H3>VOEvent Status</H3>";

print "Transport Status: <font color='green'>" . 
      $broker_soap->transport()->status() . "</font><BR>" .
      "Stored: <a href='$path'>". $ivorn . "</a><br>\n";

print "<H3>Observation Status</H3>";
 
my $obs_return = $obs_result->result(); 
print "Transport Status:  <font color='green'>" . 
      $agent_soap->transport()->status() . "</font><BR>\n";

$obs_return =~ s/>/&gt;/g;
$obs_return =~ s/</&lt;/g;
if ( $obs_return eq "QUEUED OK" ) {
   print "Result: <font color='green'>$obs_return</font><br>\n";
} elsif ( $obs_return eq "DONE OK" ) {
   print "Result: <font color='green'>$obs_return</font> (attempted to queue on all telescopes)<br>\n";
} else {
   print "Result: <font color='red'>$obs_return</font><br>\n";
}
      
$voevent =~ s/>/&gt;/g;
$voevent =~ s/</&lt;/g;
print "<H3>VOEvent Message</H3><PRE>". $voevent . "</PRE>";
      
print $footer;

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
 
 my $decimal_ra = $ra_hour*15.0 + ($ra_min/60.0) + ($ra_sec/3600.0);
 my $decimal_dec;
 if ( $dec_deg =~ "-" ) {
    $decimal_dec = $dec_deg - ($dec_min/60.0) - ($dec_sec/3600.0);
 } else {   
    $decimal_dec = $dec_deg + ($dec_min/60.0) + ($dec_sec/3600.0);
 }
 $decimal_dec =~ s/\+// if $decimal_dec eq "+";
 
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
  my $error = shift;
  my $observation = shift;
  my $query = shift;
  my $document = shift;
  
  print "Content-type: text/html\n\n";       
  print "<HTML><HEAD>Error</HEAD><BODY><FONT COLOR='red'>".
        "Error: $error</FONT><BR><BR>";
  if ( defined $query ) {
     print "<P><PRE>" . Dumper( $query ). "</PRE></P>";
  }
  if ( defined $observation ) {
     print "<P><PRE>" . Dumper( $observation ). "</PRE></P>";
  }  
  if ( defined $document ) {
     $document =~ s/>/&gt;/g;
     $document =~ s/</&lt;/g;     
     print "<P><PRE>" . Dumper( $document ). "</PRE></P>";
  }  
  print "</BODY></HTML>";
}

