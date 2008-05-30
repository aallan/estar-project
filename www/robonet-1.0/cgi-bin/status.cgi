#!/software/perl-5.8.8/bin/perl

  #use lib $ENV{"ESTAR_PERL5LIB"};     
  use lib "/work/estar/third_generation/lib/perl5";
  use eSTAR::Util;
  use eSTAR::Observation;
  use eSTAR::RTML::Parse;
  use eSTAR::RTML::Build;
  use XML::Document::RTML;
  
  #use Config::User;
  use File::Spec;
  use Time::localtime;
  use Data::Dumper;
  use Fcntl qw(:DEFAULT :flock);
  use DateTime;
  use DateTime::Format::ISO8601;
   
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
  
  # fix dir string to be date string
  my $dir = $query{dir};
  my $date = $dir;
  $date =~ s/01-/Jan / if $dir =~ /01-/;
  $date =~ s/02-/Feb / if $dir =~ /02-/;
  $date =~ s/03-/Mar / if $dir =~ /03-/;
  $date =~ s/04-/Apr / if $dir =~ /04-/;
  $date =~ s/05-/May / if $dir =~ /05-/;
  $date =~ s/06-/Jun / if $dir =~ /06-/;
  $date =~ s/07-/Jul / if $dir =~ /07-/;
  $date =~ s/08-/Aug / if $dir =~ /08-/;
  $date =~ s/09-/Sep / if $dir =~ /09-/;
  $date =~ s/10-/Oct / if $dir =~ /10-/;
  $date =~ s/11-/Nov / if $dir =~ /11-/;
  $date =~ s/12-/Dec / if $dir =~ /12-/;
  $date = "Current Month" unless defined $date;

  $header =~ s/PAGE_TITLE_STRING/Robonet-1.0 Observation Status ($date)/g;
  $header =~ s/<title>/<link rel="stylesheet" HREF="..\/css\/box.css" TYPE="text\/css"><title>/;

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
 
# M A I N   L O O P  #########################################################
  
  my $dir = File::Spec->catdir( File::Spec->rootdir(), "home", "estar", 
                                ".estar", "user_agent", "state" );
  $dir = File::Spec->catdir( $dir, $query{dir} ) if defined $query{dir};
  				
  my ( @files );
  if ( opendir (DIR, $dir )) {
     foreach ( readdir DIR ) {
  	push( @files, $_ ); 
     }
     closedir DIR;
  } else {
     error("Can not open state directory ($dir) for reading");      
  } 
  my @sorted = sort {-M "$dir/$a" <=> -M "$dir/$b"} @files;
  @files = @sorted;
  
  # NB: first 2 entries in a directory listing are '.' and '..'
  print "Content-type: text/html\n\n"; 
  print $header;
  print "<SCRIPT SRC='../js/boxover.js'></SCRIPT>\n";
  
  print "<P>Observation status at <font color='red'>" . 
        timestamp() . "</font><br>";

  if ( defined $query{dir} ) {
     print "More information available on the <a href='./scoring.cgi?dir=$query{dir}'>scoring status</a> pages.<br>";
  } else {
     print "More information available on the <a href='./scoring.cgi'>scoring status</a> pages.<br>";
  }   
 
 print '<p><APPLET archive="http://estar5.astro.ex.ac.uk/robonet-1.0/applet/GeochronApplet.jar" code="GeochronApplet" width="550" height="275">';
 print '  <param name="dayImageURL" value="http://estar5.astro.ex.ac.uk/robonet-1.0/jpg/day.jpg">';
 print '  <param name="nightImageURL" value="http://estar5.astro.ex.ac.uk/robonet-1.0/jpg/night.jpg">';
 print '</applet></p>';
 
  print "Time at FTS is <font color='red'>".eSTAR::Util::time_at_FTS()."</font> (Australia/Sydney)<br>\n";
  print "Time at LT is <font color='red'>".eSTAR::Util::time_at_LT()."</font> (Atlantic/Canary)<br>\n";
  print "Time at FTN is <font color='red'>".eSTAR::Util::time_at_FTN()."</font> (Pacific/Honolulu)<br>\n";
  print "Time in UK is <font color='red'>".eSTAR::Util::time_in_UK()."</font> (Europe/London)<br>\n";
	
  print "<font size='-2'><p>Jan 2006 | ". 
        "Feb 2006 | ". 
        "Mar 2006 | ". 
        "Apr 2006 | ". 
        "May 2006 | ". 
        "<a href='./status.cgi?dir=06-2006'>Jun 2006</a> | ". 
        "<a href='./status.cgi?dir=07-2006'>Jul 2006</a> | ". 
        "<a href='./status.cgi?dir=08-2006'>Aug 2006</a> | ". 
        "<a href='./status.cgi?dir=09-2006'>Sep 2006</a> | ". 
        "<a href='./status.cgi?dir=10-2006'>Oct 2006</a> | ". 
        "<a href='./status.cgi?dir=11-2006'>Nov 2006</a> | ". 
        "<a href='./status.cgi?dir=12-2006'>Dec 2006</a></p>";
  print "<p><a href='./status.cgi?dir=01-2007'>Jan 2007</a> | ". 
        "<a href='./status.cgi?dir=02-2007'>Feb 2007</a> | ". 
        "<a href='./status.cgi?dir=03-2007'>Mar 2007</a> | ". 
        "<a href='./status.cgi?dir=04-2007'>Apr 2007</a> | ". 
        "<a href='./status.cgi?dir=05-2007'>May 2007</a> | ". 
        "<a href='./status.cgi?dir=06-2007'>Jun 2007</a> | ". 
        "<a href='./status.cgi?dir=07-2007'>Jul 2007</a> | ". 
        "<a href='./status.cgi?dir=08-2007'>Aug 2007</a> | ". 
        "<a href='./status.cgi?dir=09-2007'>Sep 2007</a> | ". 
        "<a href='./status.cgi?dir=10-2007'>Oct 2007</a> | ". 
        "<a href='./status.cgi?dir=11-2007'>Nov 2007</a> | ". 
        "Dec 2007</p>";
 my $this_year = "<p>Jan 2008 | ". 
        "<a href='./status.cgi?dir=02-2008'>Feb 2008</a> | ". 
        "<a href='./status.cgi?dir=03-2008'>Mar 2008</a> | ". 
        "<a href='./status.cgi?dir=04-2008'>Apr 2008</a> | ". 
        "<a href='./status.cgi?dir=05-2008'>May 2008</a> | ". 
        "Jun 2008 | ". 
        "Jul 2008 | ". 
        "Aug 2008 | ". 
        "Sep 2008 | ". 
        "Oct 2008 | ". 
        "Nov 2008 | ". 
        "Dec 2008</p></font>";


  my $month = localtime->mon() + 1;
  $month = "0$month" if $month < 10;
  $this_year =~ s/\?dir=$month-2008//;
  print $this_year;	
		 
  print "<font size='-2'><table border='0' width='95%'>\n"; 
  print "<tr><th align='left'>Target</th>".
	"<th align='left'>Type</th>".
        "<th align='left'>Priority</th>".
        "<th align='left'>Date</th>".
        "<th align='left'>Exposure</th>".
        "<th align='left'>Filter</th>".
        "<th align='left'>Node</th>".
	"<th align='left'>Status?</th></tr>\n";
	
  foreach my $i ( 0 ... $#files ) {
#   for ( my $i = $#files; $i >= 0; $i = $i - 1 ) {
   
     #print "'".$files[$i]."'\n";
     next if $files[$i] =~ m/\./;
     next if $files[$i] =~ m/\.\./;
     next if $files[$i] =~ m/^\d{4}$/;
     next if $files[$i] =~ m/^\d{2}-\d{4}$/;
   
     #print "<tr><td colspan='5'>$files[$i]</td></tr>";
     
     print "<tr>";
     #print "<td><font color='grey'>$files[$i]</font></td>";
     my $object;
     eval { $object = thaw( $dir, $files[$i] ); };
     
     # QUERY OBSERVATION OBJECT ------------------------------------------
     if ( $@ ) {
        print "<td><font color='grey'>$files[$i]</font></td>";
        print "<td colspan='5'><font color='red'>$@</font></td>\n";
     } else {
        #print "<td><font color='green'>OK</font></td>\n";
	
	my $status = $object->status();
	my $node = $object->node();
	
	#print "$files[$i] = $node<br>";
	
        my ($node_name, $score_reply);
	eval { ($node_name, $score_reply) = $object->highest_score(); };
	if ( $@ ) {
	  error( "$@" );
	  exit;
	}  
	$node = "FTN" if $node eq "estar3.astro.ex.ac.uk:8077";
	$node = "FTN Proxy" if $node eq "132.160.98.239:8080/axis/services/NodeAgent";
	$node = "LT" if $node eq "estar3.astro.ex.ac.uk:8078";
	$node = "LT Proxy" if $node eq "161.72.57.3:8080/axis/services/NodeAgent";
	$node = "FTS" if $node eq "estar3.astro.ex.ac.uk:8079";  
	$node = "FTS Proxy" if $node eq "150.203.153.202:8080/axis/services/NodeAgent";
        $node = "UNKNOWN" unless defined $node;
	
	my $score;
        eval { $score = $score_reply->score() if defined $score_reply; };
        if ( $@ ) {
           error( "$@");
           exit;
        }
        $score = "undef" unless defined $score;
	
	
	# Look for an observation request
	# case: normal operations
	my $obs;
	eval { $obs = $object->obs_request(); };
	if ( $@ ) {
	   error( "$@");
	   exit;
	}
	
	# If that's not there we might have a final response
	# case: timeout error
	my $unknown = 0;
	unless ( defined $obs ) {
	   eval { $obs = $object->observation(); };
	   $unknown = 1;
	   if ( $@ ) {
	      error( "$@");
	      exit;
	   }	
        }
	
	# if that's not there we might have an obs reply
	# case: expired
	unless ( defined $obs ) {
	   eval { $obs = $object->obs_reply(); };
	   $unknown = 1;
	   if ( $@ ) {
	      error( "$@");
	      exit;
	   }	
        }
	
	# last chance
	# case: expired & timeout error
	unless ( defined $obs ) {
	   eval { $obs = $object->update(); };
	   $unknown = 1;
	   if ( $@ ) {
	      error( "$@");
	      exit;
	   }	
        }
	
	# NB: If we have a timeout error and we get no response
	# we'll never know about it, so ignore that case.
		
        my ($target, $priority, $ra, $dec, $group_count, $series_count, $exposure, @time, $type, $filter, $project);
	if( defined $obs ) {
           $target = $obs->target();
           $ra = $obs->ra();
           $dec = $obs->dec();
	   $group_count = $obs->groupcount();
	   $series_count = $obs->seriescount();
	   $exposure = $obs->exposure();
	   @time = $obs->timeconstraint();
	   $type = $obs->targettype();
	   $filter = $obs->filter();
	   $priority = $obs->priority();
	   $project = $obs->project() if $obs->isa("XML::Document::RTML");
	   #print "\$obs->isa() = " . $obs->isa("XML::Document::RTML") . ", $project is" . $obs->project() . "<br>";
        }
	
        # TARGET - 1 ---------------------------------------------------
        $target = "Unknown" unless defined $target;

	my $full_name = $target;
	if ( $target =~ m/OB(\d{5})/ ) {
	   $full_name =~ s/OB(\d{2})/OGLE-20\1-BLG-/;
	}
	if ( $target =~ m/KB(\d{5})/ ) {
	   $full_name =~ s/KB(\d{2})/MOA-20\1-BLG-/;
	}
		
        print "<td><font color='grey'>";
	if ( $target =~ m/OB\d{5}/ ||  $target =~ m/KB\d{5}/ ) {
           my $name = $target;
	   $name =~ s/OB\d{2}/blg-/;
	   my $url;
	   if( $full_name =~ "2006" ) {
	      $url = 'http://star-www.st-and.ac.uk/~kdh1/cool/' . $name . '.html';
	   } elsif( $full_name =~ "2007" ) {
	      $url = 'http://robonet.astro.livjm.ac.uk/~robonet/newcode/cgi-bin/event_pages.cgi?event=' . $target;	
	   } else {
              $url = 'http://robonet.lcogt.net/~robonet/newcode/cgi-bin/event_pages.cgi?event=' . $target;
           }
           print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Co-ordinates] body=[<table><tr><td width=25px><b>RA:</b></td><td><center>$ra</center></td></tr><tr><td><b>Dec:</b></td><td><center>$dec</center></td></tr></table>]' >";
	   print "<A HREF='$url'>$full_name</A>";
           print "</DIV>";
	   
	   
        } elsif ( $target =~ m/ESSENCE/ ) {
           my $name = $target;
	   $name =~ s/ESSENCE-//;
           if ( $name =~ m/\p{IsAlpha}$/ ) {
              chop $name;
           }
	   my $url = 'http://ctiokw.ctio.noao.edu/~sm/w/public/' . $name . '/';	
           print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Co-ordinates] body=[<table><tr><td width=25px><b>RA:</b></td><td><center>$ra</center></td></tr><tr><td><b>Dec:</b></td><td><center>$dec</center></td></tr></table>]' >";
	   print "<A HREF='$url'>$full_name</A>";
           print "</DIV>";
	} else {
           print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Co-ordinates] body=[<table><tr><td width=25px><b>RA:</b></td><td><center>$ra</center></td></tr><tr><td><b>Dec:</b></td><td><center>$dec</center></td></tr></table>]' >";
           print "$full_name";
           print "</DIV>";
        }	
	print "</font></td>\n";

        # TARGET TYPE - 2 ----------------------------------------------
	

        print "<td>";	     
	
        if ( $group_count == 3 && $exposure == 30 && $target =~ m/OB\d{5}/ ||
             !defined $series_count && !defined $group_count && $exposure == 90 && $target =~ m/OB\d{5}/ ) {
	     
	   my $event = $target;
	   $event =~ s/OB(\d{2})/OGLE-20\1-BLG-/;
           my $voevent =
	    "http://www.estar.org.uk/voevent/eSTAR/uk.org.estar/pl.edu.ogle/" .
	    $event . ".xml";	
	     
	   print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Message IVORN] body=[ivo://uk.org.estar/pl.edu.ogle#".$event."]' >";
           print "<A HREF='$voevent'>event</A>";
           print "</DIV>";
	
	} elsif ( $target =~ m/ESSENCE/ ) {
	
	   my $event = $target;
	   $event =~ s/ESSENCE-//;
           my $voevent =
	    "http://www.estar.org.uk/voevent/NOAO/voevent.noao.edu/essence/" .
	    $event . ".xml";	
	   print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Message IVORN] body=[ivo://voevent.noao.edu/essence#".$event."]' >";
           print "<A HREF='$voevent'>event</A>";
           print "</DIV>";	
	
	} else {
           if ( $type eq 'toop' ) {
	      print "<font color='blue'>override</font>"; 
	   } else {
              print "<font color='grey'>$type</font>"; 
	   }
	}  
	print "</td>\n";    

        # PRIORITY - 3 -----------------------------------------------------

        print "<td>";
        print "<font color='grey'>$priority</font>";
        print "</DIV>";
        print "</td>\n";	 

	# TIMESTAMP - 4 ------------------------------------------------
	
	my $date = $time[0];
	$date =~ s/T\d{2}:\d{2}:\d{2}.\d{4}$//;
	print "<td>";
        print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Time Constraints] body=[<table><tr><td><b>Start:</b></td><td>$time[0]</td></tr><tr><td><b>End:</b></td><td>$time[1]</td></tr></table>]' >";
        print "<font color='grey'>$date</font>";
        print "</DIV>";
        print "</td>\n";
	  
	# EXPOSURE - 5 ----------------------------------------------  
	print "<td><font color='grey'>";
	if ( defined $series_count && defined $group_count ) {
	   print "$series_count&times;($group_count&times;$exposure)";
	} elsif ( defined $series_count && !defined $group_count ) {
	   print "$series_count&times;(1&times;$exposure)";
	} elsif ( !defined $series_count && defined $group_count ) {
	   print "1&times;($group_count&times;$exposure)";
	} elsif ( !defined $series_count && !defined $group_count ) {
	   print "$exposure";
	} else {
	
	}
        print " sec" if defined $exposure; 
	print "</font></td>\n";
	
	
	# FILTER - 6 -----------------------------------------------------
	
	
	print "<td>";
        print "<font color='grey'>$filter</font>";
        print "</DIV>";
        print "</td>\n";	
	
	# NODE - 7 ---------------------------------------------------------
	
	print "<td>";
        my $expire;
	my $parse_error = 0;
	eval { $expire = expired( @time ); };
	if( $@ ) {
	   my $error = "$@";
           print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Error] body=[$error]' >";
           print " <b><font color='red'>ERROR</font></b>";
           print "</DIV>";
	   $parse_error = 1;	
	} else {
	   if( $unknown == 1 ) {
              print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Error] body=[Returned observation not in database.<br>Possible timeout at Node Agent?]' >";
              print " <b><font color='red'>ERROR</font></b>";
              print "</DIV>";
	   } elsif( $node eq "UNKNOWN" ) {
              print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Error] body=[Observations were queued without a score request.<br>Queued, but at unknown telescope]' >";
              print " <b><font color='red'>ERROR</font></b>";
              print "</DIV>";	      
           } elsif ( $target =~ m/OGLE/ ) {
              print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Error] body=[<table><tr><td><b>$node_name</b> ($node)</td></tr><tr><td><b>Score:</b> $score</td></tr><tr><td>&nbsp;</td></tr><tr><td>OGLE target with incorrectly formated name</td></tr><tr><td>Target name will not trigger pipeline?</td></tr><tr><td>Use name in format: OB07xxx</td></tr></table>]' >";
              print "<font color='red'><b>ERROR</b></font>";
              print "</DIV>";
           } elsif ( !( $expire == -1 || $expire == 0 ) && $status eq "update" ) {
              print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Warning] body=[<table><tr><td><b>$node_name</b> ($node)</td></tr><tr><td><b>Score:</b> $score</td></tr><tr><td>&nbsp;</td></tr><tr><td>The observation has expired.</td></tr><tr><td>But no final return document was received.</td></tr></table>]' >";
              print "<font color='orange'><b>WARN</b></font>";
              print "</DIV>";
	   } else {
              print "<DIV TITLE='offsetx=[-75] cssbody=[popup_body] cssheader=[popup_header] header=[Best Score] body=[<table><tr><td><b>$node_name</b></td></tr><tr><td><b>Score:</b> $score</td></tr></table>]' >";
              print "<font color='grey'>$node</font>";
              print "</DIV>";
           } 
	}  
        print "</td>\n";


		
	# STATUS - 8 ---------------------------------------------------
	print "<td>";
	if ( defined $project ) {
	   print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Unique ID] body=[<table><tr><td>".$files[$i]."</td></tr><tr><td><b>Project:</b> ". $project ."</td></tr></table>]' >";
	} else {
	   print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Unique ID] body=[".$files[$i]."]' >";
	}
	if ( $status eq "running" ) {
	   if ( $expire == -1 || $expire == 0 ) {
              print "<font color='grey'>Queued</font>";
	   } else {   
              print "<font color='orange'>No response</font>";
           }

        } elsif ( $parse_error == 1 ) {
           my @updates = $object->update();
           my $num = scalar @updates;
           print "<font color='red'>Error";
           print " ($num)" if $num > 0;
           print "</font>";	
	   
	} elsif ( $status eq "failed" ) {
           print "<font color='red'>Failed</font>";
	   
	} elsif ( $status eq "update" ) {
           my @updates = $object->update();
           my $num = scalar @updates;
	   if( $expire == -1 || $expire == 0 ) {
	       print "<font color='green'>In progress";
               print " ($num)" if $num > 0;
               print "</font>";
	   } else {
               print "<font color='blue'>Expired";
               print " ($num)" if $num > 0;
               print "</font>";
           }
	   
	} elsif ( $status eq "incomplete" ) {
           my @updates = $object->update();
           my $num = scalar @updates;
           print "<font color='blue'>Incomplete";
           print " ($num)" if $num > 0;
           print "</font>";

	} elsif ( $status eq "returned" ) {
           my @updates = $object->update();
           my $num = scalar @updates;
           print "<font color='green'>Returned";
           print " ($num)" if $num > 0;
           print "</font>";
	   
	} else {
           print "<font color='grey'>$status</font>";
	}
	print "</DIV>";
	
 

	print "</td>\n";
	
     }
     print "</tr>\n";
  }
  print "</table></font>\n";		
  print $footer;
  
  
  exit;
  
# S U B - R O U T I N E S #################################################

  sub by_last_mod {
    # vars $a and $b automatically passed in
  
    # perl function 'stat' returns array of info on a file
    # 10th element of the stat array is last modified date,
    # returned as number of seconds since 1/1/1970.
    my $adate = (stat($a))[9]; # get last modified date
    my $bdate = (stat($b))[9]; # get last modified date
  
    return $adate <=> $bdate;
  }
 
  sub error {
    my $error = shift;
  
    print "Content-type: text/html\n\n";       
    print "<HTML><HEAD>Error</HEAD><BODY>\n";
    print "<FONT COLOR='red'>Error: $error</FONT>\n";
    print "</BODY></HTML>";
  }
  
  sub thaw {
    my $state_dir = shift;
    my $id = shift;

    my $object;
   
    # check we actually have an $id
    return undef unless defined $id;
   
    # DE-SERIALISE OBJECT
    # ===================
    my $observation_object;
    my $file = File::Spec->catfile( $state_dir, $id );
    
    unless ( open ( SERIAL, "<$file" ) ) {
       die "Unique ID not in state directory";
    } else {
       unless ( flock( SERIAL, LOCK_EX ) ) {
         die "Unable to acquire exclusive lock: $!";
       }
      
       # deserialise the object  
       undef $/;
       my $string = <SERIAL>;
       close (SERIAL);
       $object = eval $string;
    }    
    return $object;
  }


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
  
  sub expired {
     my $start = shift;
     my $end = shift;
     my $current = timestamp();
     
     # hack for a limited set of broken observations
     $start =~ s/ /\+/;
     $end =~ s/ /\+/;
     
     chop $end if $end =~ /.\d{4}$/;
     chop $end if $end =~ /.\d{3}$/;
     #$current =~ s/.\d{4}$//;
   
     my $iso8601 = DateTime::Format::ISO8601->new;
     my $end_dt;
     $end_dt = $iso8601->parse_datetime( $end );
     $end_dt->add( days => 1 );
     
     my $current_dt = $iso8601->parse_datetime( $current );
     my $interval = DateTime->compare($current_dt, $end_dt);
     
     die( "Problem finsing expiry time" ) unless defined $interval;
     return $interval;

  }
