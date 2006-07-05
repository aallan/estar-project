#!/software/perl-5.8.6/bin/perl

use Time::localtime;
use Data::Dumper;
use Astro::VO::VOEvent;
use SOAP::Lite;
use Digest::MD5 'md5_hex';
use URI;
use HTTP::Cookies;
use LWP::UserAgent;
use Config::Simple;

my $host = "estar3.astro.ex.ac.uk";
my $port = "9099";

# G R A B   U S E R  I N F O R M A T I O N ------------------------------------

my $user = $ENV{REMOTE_USER};
my $db;
eval { $db = new Config::Simple( "../db/user.dat" ); };
if ( $@ ) {
   error( "$@" );
   exit;   
}  

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


# V A L I D A T E ------------------------------------------------------------

my $valid = 1;
my $error;

my @validation_errors;
if ( $query{previous_ivorn} ne "" ) {
   unless ( $query{previous_ivorn} =~ "ivo://" ) {
       push @validation_errors, 
       "<span class='error'>Error: Invalid citation IVORN</span>";
   }      
   unless ( $query{cite_type} ne "" ) {
       push @validation_errors, 
       "<span class='error'>Error: Citation IVORN given, but no type?</span>";   
   }
   unless ( $query{previous_ivorn} =~ "ivo://" && $query{cite_type} ne "" ) {
       $valid = 0;
   }
}

if ( $query{contact_name} ne "" ) {
   unless ( $query{contact_name} =~ m/\w+\s\w/ ) {
      $valid = 0;
      push @validation_errors, 
       "<span class='error'>Error: Invalid contact name</span>";
   }    

}

if ( $query{contact_email} ne "" ) {
   unless ( $query{contact_email} =~ m/\w+@\w+/ ) {
      $valid = 0;
      push @validation_errors, 
       "<span class='error'>Error: Invalid contact email address</span>";
   } 

}

if ( $query{contact_phone} ne "" ) {
   my $phone_flag = 0;
   $phone_flag = 1 if $query{contact_phone} =~ m/\+\d{2}-\d{4}-\d{6}/;
   $phone_flag = 1 if $query{contact_phone} =~ m/\+\d{1}-\d{3}-\d{3}-\d{4}/;
   unless ( $phone_flag == 1 ) {
      $valid = 0;   
      push @validation_errors, 
       "<span class='error'>Error: Invalid contact phone number</span>";
   }    

}

if ( $query{short_name} ne "" ) {
   #unless ( $query{short_name} eq "RAPTOR" ||
   #         $query{short_name} eq "eSTAR" ) {
   #   $valid = 0;
   #   push @validation_errors, 
   #    "<span class='error'>Error: Invalid project name</span>";
   #}
}

if ( $query{facility} ne "" ) {
   #unless ( $query{facility} eq "Robonet-1.0" ||
   #         $query{facility} eq "TALONS" ) {
   #   $valid = 0;
   #   push @validation_errors, 
   #    "<span class='error'>Error: Invalid facility</span>";
   #}

}

if ( $query{how_reference} ne "" ) {
   unless ( $query{how_reference} =~ "http://" ) {
      $valid = 0;
      push @validation_errors, 
       "<span class='error'>Error: Not a valid URL in <How> reference</span>";
   }    

} 

my $ra_flag = 0;
$query{ra} =~ s/:/ /g;
$ra_flag = 1 if $query{ra} =~ m/^\d{2}\s\d{2}\s\d{2}\.\d{1}$/;
$ra_flag = 1 if $query{ra} =~ m/^\d{2}\s\d{2}\s\d{2}$/;
$valid = 0 unless $ra_flag == 1;
unless ( $ra_flag == 1 ) {
   push @validation_errors, 
    "<span class='error'>Error: R.A. is not in valid format</span>";
}    

my $dec_flag = 0;
$query{dec} =~ s/:/ /g;
$dec_flag = 1 if $query{dec} =~ m/^\d{2}\s\d{2}\s\d{2}\.\d{1}$/;
$dec_flag = 1 if $query{dec} =~ m/^\d{2}\s\d{2}\s\d{2}$/;
$dec_flag = 1 if $query{dec} =~ m/^\+\d{2}\s\d{2}\s\d{2}\.\d{1}$/;
$dec_flag = 1 if $query{dec} =~ m/^\+\d{2}\s\d{2}\s\d{2}$/;
$dec_flag = 1 if $query{dec} =~ m/^-\d{2}\s\d{2}\s\d{2}\.\d{1}$/;
$dec_flag = 1 if $query{dec} =~ m/^-\d{2}\s\d{2}\s\d{2}$/;
$valid = 0 unless $dec_flag == 1;
unless ( $dec_flag == 1 ) {
   push @validation_errors, 
    "<span class='error'>Error: Dec. is not in valid format</span>";
}   

unless( $query{time} =~ m/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/ ) {
   $valid = 0;
   push @validation_errors, 
    "<span class='error'>Error: Time stamp is not in valid format</span>";
}   

if ( $valid == 0 ) {
   eval { open( FORM, "./index.cgi |" ) };
   if ( $@ ) {
      error( "$@" );
      exit;
   }
   my $page;
   {
      $/ = undef;
      $page = <FORM>;
   }   
   close (FORM);
   
   my $error_list ="";
   foreach my $j ( 0 ... $#validation_errors ) {
      $error_list = $error_list . $validation_errors[$j];
   }  
   $error_list = '<table width="95%"><tr><td><strong><font color="red"><u>Validation Errors</u></font></strong></td></tr><tr><td>'.$error_list.'</td></tr></table>';
   
   my @split = split '<center>', $page;
   my $new_page = $split[0] . "<center>$error_list";
   foreach my $i ( 1 ... $#split ) {
      $new_page = $new_page . $split[$i];
   }   
   
   print $new_page;
   exit;
}

# G E N E R A T E   V O E V E N T --------------------------------------------

my $publisher_ivorn = "ivo://uk.org.estar";
my $partial_author_ivorn = $db->param( "$user.author_ivorn" );

my $ivorn = $publisher_ivorn . "/" . $partial_author_ivorn . "#" . "manual/";
if( $query{facility} ne "" ) {
   my $facility = $query{facility};
   $facility =~ s/ /_/g;
   $ivorn = $ivorn . lc($facility) ."/";
}
if( $query{instrument} ne "" ) {
   my $instrument = $query{instrument};
   $instrument =~ s/ /_/g;
   $ivorn = $ivorn . lc($instrument) . "/";
}      
$ivorn = $ivorn . timestamp();

my %observation;
$observation{ID} = $ivorn;

if ( $query{role} ne "" ) {
  $observation{Role} = $query{role};
} else {
  error( "Must define 'role' of message", undef, \%query );
  exit;
}
if ( $query{description} ne "" ) {
  $observation{Description} = $query{description}
}

if( $query{cite_type} ne "" && $query{previous_ivorn} ) {
   $observation{Citations} = [ { ID   => $query{previous_ivorn}, 
                                 Cite => $query{cite_type} } ];
}				 

$observation{Who} = { Publisher => "ivo://" . $partial_author_ivorn ."#",
                      Date      => timestamp(),
                      Contact   => { Name        => $query{contact_name},
                                     Institution => $query{short_name},
                                     Address     => $query{title},
                                     Telephone   => $query{contact_phone},
                                     Email       => $query{contact_email} } };
my ( $ra, $dec );
if ( $query{ra} ne "" && $query{dec} ne "" ) {				       
  ($ra, $dec) = convert_from_sextuplets( $query{ra}, $query{dec} );
  if ( $query{dist_error} ne "" ) {
     $query{dist_error} = $query{dist_error}/60.0;
     $observation{WhereWhen} = { RA => $ra, 
                                 Dec => $dec, 
			         Error => $query{dist_error},
                                 Time => $query{time}
			       };
  } else {
     $observation{WhereWhen} = { RA => $ra, 
                                 Dec => $dec, 
                                 Time => $query{time}
			       };  
  }			       
}			          

my @what;
if ( $query{param_1_name} && $query{param_1_ucd} && 
     $query{param_1_units} && $query{param_1_value} ) {
     
   push @what, { Name  => $query{param_1_name},
                 UCD   => $query{param_1_ucd},
	         Value => $query{param_1_value},  
                 Units => $query{param_1_units} }
}     
if ( $query{param_2_name} && $query{param_2_ucd} && 
     $query{param_2_units} && $query{param_2_value} ) {
     
   push @what, { Name  => $query{param_2_name},
                 UCD   => $query{param_2_ucd},
	         Value => $query{param_2_value},  
                 Units => $query{param_2_units} }
}   
if ( $query{param_3_name} && $query{param_3_ucd} && 
     $query{param_3_units} && $query{param_3_value} ) {
     
   push @what, { Name  => $query{param_3_name},
                 UCD   => $query{param_3_ucd},
	         Value => $query{param_3_value},  
                 Units => $query{param_3_units} }
}   
if ( $query{param_4_name} && $query{param_4_ucd} && 
     $query{param_4_units} && $query{param_4_value} ) {
     
   push @what, { Name  => $query{param_4_name},
                 UCD   => $query{param_4_ucd},
	         Value => $query{param_4_value},  
                 Units => $query{param_4_units} }
}  
$observation{What} = \@what if defined $what[0];
 
if( $query{how_reference} ne "" ) {
   my $type;
   if ( lc($query{how_reference}) =~ "rtml" ) {
      $type = "rtml";
   } else {
      $type = "url";
   } 
   my $name = $query{facility} if $query{facility} ne "";
   $name = $query{instrument} if $query{instrument} ne "";
        
   $observation{How} = { Reference => { URL  => $query{how_reference},
                                       Type => $type,
				       Name => $name } };
} 

if ( $query{inference_name} ne "" && 
     $query{inference_concept} ne "" &&
     $query{inference_relation} ne "" ) {
 $observation{Why} = [ { Inference => { Probability  => $query{probability},
                                        Relation     => $query{inference_relation},
                                        Name         => $query{inference_name},
                                        Concept      => $query{inference_concept}} } ];
}
 
my $object = new Astro::VO::VOEvent( );
my $document = $object->build( %observation );

# S U B M I T   E V E N T   M E S S A G E ------------------------------------

# end point
my $endpoint = "http://" . $host . ":" . $port;
my $uri = new URI($endpoint);

# create a user/passwd cookie
my $cookie = make_cookie( "agent", "InterProcessCommunication" );

my $cookie_jar = HTTP::Cookies->new();
$cookie_jar->set_cookie(0, user => $cookie, '/', $uri->host(), $uri->port());

# create SOAP connection
my $soap = new SOAP::Lite();

$soap->uri( "urn:/event_broker" ); 
$soap->proxy($endpoint, cookie_jar => $cookie_jar);
  
# report
  
# grab result 
my $result;
eval { $result = $soap->handle_voevent(  $db->param( "$user.soap_name" ), $document ); };
if ( $@ ) {
   my $error = "$@";
   error( $error, \%observation, \%query, $document );
   exit;   
}

if ($result->fault() ) {
  error( "(" . $result->faultcode() . "): " . $result->faultstring(), \%observation, \%query, $document  );
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

my $result = $result->result();
my $path = grab_url_of_document( $result );
$result =~ s/>/&gt;/g;
$result =~ s/</&lt;/g;
print "<H3>Transport Status</H3>".
      "Transport Status: <font color='green'>" . 
      $soap->transport()->status() . "</font><BR>" .
      "Stored at: <a href='$path'>". $ivorn . "</a><br>\n";
print "Return to the <a href='http://vo.astro.ex.ac.uk/voevent/cgi-bin/index.cgi'>manual injection page</a>";
      
 
$document =~ s/>/&gt;/g;
$document =~ s/</&lt;/g;
print "<H3>VOEvent Message</H3><PRE>". $document . "</PRE>";
      
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

