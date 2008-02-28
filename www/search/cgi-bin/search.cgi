#!/software/perl-5.8.8/bin/perl

use Astro::Catalog;
use Astro::Catalog::Query::USNOA2;
use Astro::Catalog::Query::GSC;
use Astro::Catalog::Query::CMC;
use Astro::Catalog::Query::SuperCOSMOS;
use Astro::Catalog::Query::2MASS;
use Astro::Catalog::Query::Sesame;
use Astro::SIMBAD::Query;

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

# S T A R T   W R I T I N G   O U T P U T ------------------------------------

# this is my regular website template as used throughout the site
# and is here to give continuity of look and feel to the user.

if ( $query{download} eq "false" ) {
   print "Content-type: text/html\n\n";
   print "<HTML>\n";
   print "<HEAD>\n";
   print "    <TITLE>\n";
   print "    eSTAR Catalogue Results\n";
   print "    </TITLE>\n";
   print "    <STYLE TYPE='text/css'>\n";
   print "      <!--\n";
   print "        body {\n";
   print "            color: #000000;\n";
   print "            background-color: #FFFFFF;\n";
   print "            font-family: Arial, 'Times New Roman', Times;\n";
   print "            font-size: 16px;\n";
   print "        }\n";
   print "\n";
   print "        A:link {\n";
   print "            color: blue\n";
   print "        }\n";
   print "\n";
   print "        A:visited {\n";
   print "            color: blue\n";
   print "        }\n";
   print "\n";
   print "        td {\n";
   print "            color: #000000;\n";
   print "            font-family: Arial, 'Times New Roman', Times;\n";
   print "            font-size: 16px;\n";
   print "        }\n";
   print "\n";
   print "        .code {\n";
   print "            color: #000000;\n";
   print "            font-family: 'Courier New', Courier;\n";
   print "            font-size: 16px;\n";
   print "        }\n";
   print "      -->\n";
   print "   </STYLE>\n";
   print "</HEAD>\n";
   print "<BODY>\n";
   print "\n";
   print "<H2><FONT COLOR='red'>e</FONT>STAR Catalogue Broker</H2>\n\n";
   print "<A HREF='http://www.estar.org.uk/'>eSTAR Project</A><BR>\n";
   print "Astrophysics Group<BR>\n";
   print "University of Exeter<BR>\n";

} else {
   print "Content-type: text/plain\n\n"; 
}
   
# V A L I D A T E   I N P U T ------------------------------------------------

# debugging
#if ( $query{download} eq "false" ) {
#   print "<H3><U>Input Parameters</U></H3>\n\n";
#   print "<TABLE WIDTH='40%' BORDER='1' CELLPADDING='2' CELLSPACING='0'>\n";
#   foreach my $key ( sort keys %query ) {
#     print "<TR><TD><STRONG>$key</STRONG></TD> <TD>&nbsp; $query{$key}</TD></TR>\n";
#   } 
#   print "</TABLE>\n";
#}

# debugging
if ( $query{download} eq "false" ) {
   print "\n<H3><U>Validating Input</U></H3>\n\n";
}

# check the radius is defined!
unless ( defined $query{radius} && exists $query{radius} && $query{radius} ne ''  ) {
   if ( $query{download} eq "false" ) {
      print "<FONT COLOR='orange'>Warning: Search radius is undefined...</FONT><BR>\n";
      print "<FONT COLOR='orange'>Warning: Defaulting to a cone radius of 10 arcminutes</FONT><BR>\n";
   }
   $query{radius} = 10;
}

# check the equinox is defined!
unless ( defined $query{equinox} && exists $query{equinox} && $query{equinox} ne ''  ) {
   if ( $query{download} eq "false" ) {
      print "<FONT COLOR='orange'>Warning: Equinox is undefined...</FONT><BR>\n";
      print "<FONT COLOR='orange'>Warning: Defaulting to J2000</FONT><BR>\n";
   }
   $query{equinox} = "J2000";
}


# polymorphically select the catalogue query
my $module = "Astro::Catalog::Query::$query{catalogue}";

# build the query
my $query;

if ( defined $query{ra} && exists $query{ra} && $query{ra} ne '' &&
     defined $query{dec} && exists $query{dec} && $query{dec} ne '' ) {
     
   if ( $query{download} eq "false" ) {
      print "Building a query using RA and Dec...<BR>\n";
   }
   
   # need to specify 'colour' for SuperCOS and an increased timeout
   if ( $query{catalogue} eq "SuperCOSMOS" ) {
   
      $query = new $module( RA      => $query{ra}, 
                            Dec     => $query{dec},
                            Equinox => $query{equinox},
                            Radius  => $query{radius},
                            Colour  => 'UKJ',
                            Timeout => 60 );
   } else {
      $query = new $module( RA      => $query{ra}, 
                            Dec     => $query{dec},
                            Equinox => $query{equinox},
                            Radius  => $query{radius} ); 
   }
                                                    
} elsif ( defined $query{name} && exists $query{name} && $query{name} ne ''  ) {

   if ( $query{download} eq "false" ) {
      print "Querying <A HREF='http://cdsweb.u-strasbg.fr/cdsws.gml'>Sesame</A>"
         . " to resolve target <FONT COLOR='blue'>$query{name}</FONT>...<BR>\n";
   }
  
   my ( $ra, $dec );
  
   my $sesame_query = new Astro::Catalog::Query::Sesame(Target => $query{name});
   my $sesame_result; 
   eval { $sesame_result = $sesame_query->querydb(); };
   if ( $@ ) {
      if ( $query{download} eq "false" ) {
         print "<FONT COLOR='orange'>Warning: Problems making Sesame query...</FONT><BR>\n";
         print "<FONT COLOR='red'>Error: $@</FONT><BR>\n";
         print "<FONT COLOR='orange'>Warning: Falling back to " . 
               " <A HREF='http://simbad.u-strasbg.fr/'>SIMBAD</A>...</FONT><BR>\n";
      }     

      my $simbad_query = new Astro::SIMBAD::Query( Target  => $query{name},
                                                   Timeout => 5 );
                          
      my $simbad_result;
      eval { $simbad_result = $simbad_query->querydb(); };
      if ( $@ ) {
         if ( $query{download} eq "false" ) {
           print "<FONT COLOR='red'>Error: Problems SIMBAD query...</FONT><BR>\n";     
           print "<FONT COLOR='red'>Error: Unable to resolve target</FONT><BR>\n";
           print "<FONT COLOR='red'>Error: $@</FONT><BR>\n";  
           print "\n</BODY>\n";
           print "</HTML>\n";
         } else {
           print "Unable to reolve target, queried both Sesame and SIMBAD\n";
         }
         exit;    
      }   
 
      if ( defined $simbad_result ) {   
          @object = $simbad_result->objects( );
          if ( defined $object[0] ){
             $ra = $object[0]->ra();
             $dec = $object[0]->dec();    
          }
      } else {
         if ( $query{download} eq "false" ) {
           print "Problems making SIMBAD query...<BR>\n";     
           print "<FONT COLOR='red'>Error: Unable to resolve target</FONT><BR>\n";
           print "<FONT COLOR='red'>Error: $@</FONT><BR>\n";  
           print "\n</BODY>\n";
           print "</HTML>\n";
         } else {
           print "Unable to reolve target, queried both Sesame and SIMBAD\n";
         }
         exit;    
      }         
 
   } else {
     
      my $star = $sesame_result->popstar();
      $ra = $star->ra();
      $dec = $star->dec();   
   }
      
      
   # this should only happen if we have an unresolved target, right?
   if ( $dec == 0 ) {
      if ( $query{download} eq "false" ) {
         print "<FONT COLOR='red'>Error: Bad co-ordinates returned.<BR>\n";     
         print "<FONT COLOR='red'>Error: Unable to resolve target '" . 
            $query{name} . "' using either Sesame or SIMBAD.</FONT><BR>\n";
         print "\n</BODY>\n";
         print "</HTML>\n";
      } else {
         print "Queried both Sesame and SIMBAD, but got bogus co-ordinates, target can not be resolved.\n";
      }
      exit;    
   }              
         
   if ( $query{download} eq "false" ) {
      print "R.A. $ra, Dec. $dec<BR>\n";
      print "Building a query using RA and Dec...<BR>\n";
   }   
   # need to specify 'colour' for SuperCOS and an increased timeout
   if ( $query{catalogue} eq "SuperCOSMOS" ) {
   
      $query = new $module( RA      => $ra, 
                            Dec     => $dec,
                            Equinox => $query{equinox},
                            Radius  => $query{radius},
                            Colour  => 'UKJ',
                            Timeout => 60 );
   } else {
      $query = new $module( RA      => $ra, 
                            Dec     => $dec,
                            Equinox => $query{equinox},
                            Radius  => $query{radius} ); 
   }
  
   
} else {
   if ( $query{download} eq "false" ) {
      print "Unable to build a query....<BR>\n";
      print "<FONT COLOR='red'>Error: Both R.A. &amp; Dec and the target name are undefined</FONT><BR>\n";
      print "\n</BODY>\n";
      print "</HTML>\n";
   } else {
      print "Unable to build query. R.A., Dec and target name undefined.\n";   
   }
   exit;    
}

# G R A B   C A T A L O G U E ------------------------------------------------

# debugging
if ( $query{download} eq "false" ) {
   print "\n<H3><U>Connecting to Remote Server</U></H3>\n\n";
}
  
# grab the catalogue
my $catalog;

eval { $catalog = $query->querydb(); };
if ( $@ ) {
   if ( $query{download} eq "false" ) {
      print "Problems making remote query...<BR>\n";
      print "<FONT COLOR='red'>Error: $@</FONT><BR>\n";
      print "\n</BODY>\n";
      print "</HTML>\n";
   } else {
      print "Unable to query remote catalogue server. $@\n";
   }      
   exit; 
}

if ( $query{download} eq "false" ) {
   print "Retrieved catalogue from remote server...<BR>\n";
   print "Catalogue contains " . $catalog->sizeof() . " entries<BR>\n";
}
                         
# W R I T E   O U T   C T A L O G U E ----------------------------------------

# debugging
if ( $query{download} eq "false" ) {
   print "\n<H3><U>Retrieved Catalogue</U></H3>\n\n";
}

# write to the buffer
my $buffer;
eval { $catalog->write_catalog( Format => $query{format}, File => \$buffer ); };
if ( $@ ) {
   if ( $query{download} eq "false" ) {
      print "Problems writing out catalogue...<BR>\n";
      print "<FONT COLOR='red'>Error: $@</FONT><BR>\n";
      print "\n</BODY>\n";
      print "</HTML>\n";
   } else {
      print "Unable to serialise catalogue. $@\n";
   }   
   exit; 
}

if ( $query{download} eq "false" ) {
   $buffer =~ s/</&lt;/g;
   $buffer =~ s/>/&gt;/g;
   print "<PRE>\n";
   print "$buffer\n";
   print "</PRE><BR>\n";
} else {
   print "$buffer\n";
}   

# F I N I S H   W R I T I N G   O U T P U T -----------------------------------

if ( $query{download} eq "false" ) {
   print "\n</BODY>\n";
   print "</HTML>\n";
}

exit;
