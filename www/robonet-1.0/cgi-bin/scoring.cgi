#!/software/perl-5.8.8/bin/perl

  #use lib $ENV{"ESTAR_PERL5LIB"};     
  use lib "/work/estar/third_generation/lib/perl5";
  use eSTAR::Observation;
  use eSTAR::RTML::Parse;
  use eSTAR::RTML::Build;
  use XML::Document::RTML;
  
  #use Config::User;
  use File::Spec;
  use Time::localtime;
  use Data::Dumper;
  use Fcntl qw(:DEFAULT :flock);
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

  $header =~ s/PAGE_TITLE_STRING/Robonet-1.0 Scoring ($date)/g;
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
  
  print "<P>Scoring status at <font color='red'>" . 
        timestamp() . "</font><br>";
 
  if ( defined $query{dir} ) {
     print "More information available on the <a href='./status.cgi?dir=$query{dir}'>observation status</a> pages.";
  } else {
     print "More information available on the <a href='./status.cgi'>observation status</a> pages.<br>";
  }   
  	
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
        "<a href='./status.cgi'>Jun 2008</a> | ".
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
  print "<tr><th>&nbsp</th><th>&nbsp;</th><th colspan='2' align='left'>Time</th>".
        "<th colspan='3' align='left'>Telescope</th></tr>\n";
  print "<tr><th align='left'>Unique ID</th>".
        "<th align='left'>Target</th".
	"<th align='left'>Start</th>".
        "<th align='left'>End</th>".
        "<th align='left'>LT</th>".
        "<th align='left'>FTN</th>".
        "<th align='left'>FTS</th>".
        "<th align='left'>Status</th></tr>\n";
	
  foreach my $i ( 0 ... $#files ) {
#   for ( my $i = $#files; $i >= 0; $i = $i - 1 ) {
   
     #print "'".$files[$i]."'\n";
     next if $files[$i] =~ m/\./;
     next if $files[$i] =~ m/\.\./;
     next if $files[$i] =~ m/^\d{4}$/;
     next if $files[$i] =~ m/^\d{2}-\d{4}$/;
     
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
        my ($node_name, $score_reply) = $object->highest_score();
	$node = "FTN" if $node eq "estar3.astro.ex.ac.uk:8077";
	$node = "FTN Proxy" if $node eq "132.160.98.239:8080/axis/services/NodeAgent";
	$node = "LT" if $node eq "estar3.astro.ex.ac.uk:8078";
	$node = "LT Proxy" if $node eq "161.72.57.3:8080/axis/services/NodeAgent";
	$node = "FTS" if $node eq "estar3.astro.ex.ac.uk:8079";  
	$node = "FTS Proxy" if $node eq "150.203.153.202:8080/axis/services/NodeAgent";
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

        my @split = split ":", $files[$i];
	print "<td>";
        print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Unique ID] body=[$files[$i]]' >";
        print "<font color='grey'>$split[0]</font>";
        print "</DIV>";
	print "</td>";
	
        print "<td><font color='grey'>$target</td>";
   
	# TIMESTAMP - 2 & 3 ------------------------------------------------
	
	print "<td>";
        print "<font color='grey'>$time[0]</font>";
        print "</td>\n";
	print "<td>";
        print "<font color='grey'>$time[1]</font>";
        print "</td>\n";
        	  
	# NODE -  4, 5 & 6  ---------------------------------------------------------
	
        my @nodes_list;
        push @nodes_list, "161.72.57.3:8080/axis/services/NodeAgent";      # LT
        push @nodes_list, "132.160.98.239:8080/axis/services/NodeAgent";   # FTN
        push @nodes_list, "150.203.153.202:8080/axis/services/NodeAgent";  # FTS
	
	push @nodes2_list, "estar3.astro.ex.ac.uk:8078";	# LT
	push @nodes2_list, "estar3.astro.ex.ac.uk:8077";	# FTN
	push @nodes2_list, "estar3.astro.ex.ac.uk:8079";	# FTS

        my $score_reply; 
	eval { $score_reply = $object->score_reply(); };
	if ( $@ ) {
           error( "$@");
	   exit;
	}
        foreach my $n ( 0 ... $#nodes_list ) {
	   print "<td>";
 
           my $document = ${$score_reply}{$nodes_list[$n]};
           my $this_score;
           eval { $this_score = $document->score(); };
	   if ( $@ ) {
	      $document = ${$score_reply}{$nodes2_list[$n]};
	      eval { $this_score = $document->score(); };
              if ( $@ ) {
	         print "<font color='red'>";
		 printf("%.5f", 0.0);
		 print "</font>";
	      } else {
	         if ( $this_score == $score ) {  
	             print "<font color='blue'>";    
	         } else {
	             print "<font color='grey'>";    
                 }	    
	         printf("%.5f", $this_score);
	         print "</font>" if $this_score == $score;  	      
	      }	  
	   } else { 
	      if ( $this_score == $score ) {  
	          print "<font color='blue'>";    
	      } else {
	          print "<font color='grey'>";    
              }	             
              printf("%.5f", $this_score);
	      print "</font>" if $this_score == $score;         
           }
	   print "</td>";
        }         
		
	# STATUS - 8 ---------------------------------------------------

        $target = "Unknown" unless defined $target;

	my $full_name = $target;
	if ( $target =~ m/OB(\d{5})/ ) {
	   $full_name =~ s/OB(\d{2})/OGLE-20\1-BLG-/;
	}

        my $expire;
	eval { $expire = expired( @time ); };

	print "<td>";
	if ( defined $project ) {
	   print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Target] body=[<table><tr><td><b>$target</b></td><td>&nbsp;</td></tr><tr><td><b>R.A.:</b></td><td align=right>$ra</td></tr><tr><td><b>Dec.:</b></td><td align=right>$dec</td></tr><tr><td><b>Project:</b></td><td align=right>$project</td></tr></table>]' >";
	} else {
	   print "<DIV TITLE='offsetx=[-50] cssbody=[popup_body] cssheader=[popup_header] header=[Target] body=[<table><tr><td><b>$target</b></td><td>&nbsp;</td></tr><tr><td><b>R.A.:</b></td><td align=right>$ra</td></tr><tr><td><b>Dec.:</b></td><td align=right>$dec</td></tr></table>]' >";
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
   
     chop $end if $end =~ /.\d{4}$/;
     chop $end if $end =~ /.\d{3}$/;
     #$current =~ s/.\d{4}$//;
   
     my $iso8601 = DateTime::Format::ISO8601->new;
     my $end_dt;
     $end_dt = $iso8601->parse_datetime( $end );
     $end_dt->add( days => 1 );
     
     my $current_dt = $iso8601->parse_datetime( $current );
     my $interval = DateTime->compare($current_dt, $end_dt);
     
     return $interval;

  }
