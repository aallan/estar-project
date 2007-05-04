#!/software/perl-5.8.6/bin/perl

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
  $header =~ s/PAGE_TITLE_STRING/Robonet-1.0 Performance/g;
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
				
  my ( @files );
  if ( opendir (DIR, $dir )) {
     foreach ( readdir DIR ) {
  	push( @files, $_ ); 
     }
     closedir DIR;
  } else {
     error("Can not open state directory ($dir) for reading");      
  } 
  #my @sorted = sort {-M "$dir$a" <=> -M "$dir$b"} @files;
  #@files = @sorted;

  # NB: first 2 entries in a directory listing are '.' and '..'
  print "Content-type: text/html\n\n"; 
  print $header;
  print "<SCRIPT SRC='../js/boxover.js'></SCRIPT>\n";
  
  print "<P>Observation status at <font color='red'>" . 
        timestamp() . "</font><br>";
	
  
  my ( %LT, %FTN, %FTS );
  $LT{queued} = 0;
  $LT{returned} = 0;
  $LT{incomplete} = 0;
  $LT{noresponse} = 0;
  $LT{expired} = 0;
  $LT{failed} = 0;
  $LT{total} = 0;
  
  $FTN{queued} = 0;
  $FTN{returned} = 0;
  $FTN{incomplete} = 0;
  $FTN{noresponse} = 0;
  $FTN{expired} = 0;
  $FTN{failed} = 0;
  $FTN{total} = 0;
  
  $FTS{queued} = 0;
  $FTS{returned} = 0;
  $FTS{incomplete} = 0;
  $FTS{noresponse} = 0;
  $FTS{expired} = 0;
  $FTS{failed} = 0;
  $FTS{total} = 0;  
  
#  foreach my $i ( 2 ... $#files ) {
  for ( my $i = $#files; $i >= 2; $i = $i - 1 ) {
   
     #print "'".$files[$i]."'\n";
     next if $files[$i] =~ m/^\d{4}$/;
     
     print "<tr>";
     #print "<td><font color='grey'>$files[$i]</font></td>";
     my $object;
     eval { $object = thaw( $dir, $files[$i] ); };
     
     # QUERY OBSERVATION OBJECT ------------------------------------------
     if ( $@ ) {
        print "<font color='red'>Error opening $files[$i]: $@</font>\n";
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
	
	my $obs;
	eval { $obs = $object->obs_request(); };
	if ( $@ ) {
	   error( "$@");
	   exit;
	}
	
	my $unknown = 0;
	unless ( defined $obs ) {
	   eval { $obs = $object->observation(); };
	   $unknown = 1;
	   if ( $@ ) {
	      error( "$@");
	      exit;
	   }	
        }
	
	unless ( defined $obs ) {
	   eval { $obs = $object->obs_reply(); };
	   $unknown = 1;
	   if ( $@ ) {
	      error( "$@");
	      exit;
	   }	
        }
	
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

        my $expire = expired( @time );
	
        # LT ---------------------------------------------------
       
        if ($node eq "LT" || $node eq "LT Proxy" ) {
           if( !( $expire == -1 || $expire == 0 ) && $status eq "update" ) { 
               $LT{expired} = $LT{expired} + 1;
           } elsif ( $status eq "running" ) {
	      if ( $expire == -1 || $expire == 0 ) {
                 $LT{queued} = $LT{queued} + 1;
	      } else {   
                 $LT{noresponse} = $LT{noresponse} + 1;
              }
	   } elsif ( $status eq "failed" ) {
              $LT{failed} = $LT{failed} + 1;
	   } elsif ( $status eq "update" || $status eq "incomplete" ) {
              $LT{incomplete} = $LT{incomplete} + 1;
	   } elsif ( $status eq "returned" ) {
              $LT{returned} = $LT{returned} + 1;
	   } 
           $LT{total} = $LT{total} + 1;
        }
        
        # FTN ---------------------------------------------------
       
        if ($node eq "FTN" || $node eq "FTN Proxy" ) {
           if( !( $expire == -1 || $expire == 0 ) && $status eq "update" ) { 
               $FTN{expired} = $FTN{expired} + 1;
           } elsif ( $status eq "running" ) {
	      if ( $expire == -1 || $expire == 0 ) {
                 $FTN{queued} = $FTN{queued} + 1;
	      } else {   
                 $FTN{noresponse} = $FTN{noresponse} + 1;
              }
	   } elsif ( $status eq "failed" ) {
              $FTN{failed} = $FTN{failed} + 1;
	   } elsif ( $status eq "update" || $status eq "incomplete" ) {
              $FTN{incomplete} = $FTN{incomplete} + 1;
	   } elsif ( $status eq "returned" ) {
              $FTN{returned} = $FTN{returned} + 1;
	   } 
           $FTN{total} = $FTN{total} + 1;
        }
        
        # FTS ---------------------------------------------------
       
        if ($node eq "FTS" || $node eq "FTS Proxy" ) {
            if( !( $expire == -1 || $expire == 0 ) && $status eq "update" ) { 
                $FTS{expired} = $FTS{expired} + 1;
            } elsif ( $status eq "running" ) {
	      if ( $expire == -1 || $expire == 0 ) {
                 $FTS{queued} = $FTS{queued} + 1;
	      } else {   
                 $FTS{noresponse} = $FTS{noresponse} + 1;
              }
	   } elsif ( $status eq "failed" ) {
              $FTS{failed} = $FTS{failed} + 1;
	   } elsif ( $status eq "update" || $status eq "incomplete" ) {
              $FTS{incomplete} = $FTS{incomplete} + 1;
	   } elsif ( $status eq "returned" ) {
              $FTS{returned} = $FTS{returned} + 1;
	   } 
           $FTS{total} = $FTS{total} + 1;
        }
        
     } # end of if() { } else { }        
  }    # end of for () { }
  
 
  print "<table width='80%' border='0'><tr><th>Status</th><th>Number of Requests</th><th>Percentage of Total</th></tr>"; 
  my $percentage;

  # LT
  print "<tr><th colspan='3'>LT</th></tr>";
  
  # Queued
  $percentage =  sprintf ( "%.3f", 100.0*($LT{queued}/$LT{total}) );
  print "<tr><td align='center'><font color='green'>Queued</font></td><td align='center'><font color='green'>$LT{queued}</font></td><td align='center'><font color='green'>$percentage %</font></td></tr>";
  
  # Returned
  $percentage =  sprintf ( "%.3f", 100.0*($LT{returned}/$LT{total}) );
  print "<tr><td align='center'><font color='green'>Returned</font></td><td align='center'><font color='green'>$LT{returned}</font></td><td align='center'><font color='green'>$percentage %</font></td></tr>";
  
  # Incomplete
  $percentage =  sprintf ( "%.3f", 100.0*($LT{incomplete}/$LT{total}) );
  print "<tr><td align='center'><font color='orange'>Incomplete</font></td><td align='center'><font color='orange'>$LT{incomplete}</font></td><td align='center'><font color='orange'>$percentage %</font></td></tr>";
  
  # Expired
  $percentage =  sprintf ( "%.3f", 100.0*($LT{expired}/$LT{total}) );
  print "<tr><td align='center'><font color='orange'>Expired</font></td><td align='center'><font color='orange'>$LT{expired}</font></td><td align='center'><font color='orange'>$percentage %</font></td></tr>";
  
  # Failed
  $percentage =  sprintf ( "%.3f", 100.0*($LT{failed}/$LT{total}) );
  print "<tr><td align='center'><font color='red'>Failed</font></td><td align='center'><font color='red'>$LT{failed}</font></td><td align='center'><font color='red'>$percentage %</font></td></tr>";
  
  # Failed
  $percentage =  sprintf ( "%.3f", 100.0*($LT{noresponse}/$LT{total}) );
  print "<tr><td align='center'><font color='red'>No Response</font></td><td align='center'><font color='red'>$LT{noresponse}</font></td><td align='center'><font color='red'>$percentage %</font></td></tr>";
                   
  # Total
  $percentage =  sprintf ( "%.3f", 100.0*($LT{total}/$LT{total}) );
  print "<tr><td align='center'><font color='grey'>Total</font></td><td align='center'><font color='grey'>$LT{total}</font></td><td align='center'><font color='grey'>$percentage %</font></td></tr>";
      
  # FTN
  print "<tr><th colspan='3'>FTN</th></tr>";
  
  # Queued
  $percentage =  sprintf ( "%.3f", 100.0*($FTN{queued}/$FTN{total}) );
  print "<tr><td align='center'><font color='green'>Queued</font></td><td align='center'><font color='green'>$FTN{queued}</font></td><td align='center'><font color='green'>$percentage %</font></td></tr>";
  
  # Returned
  $percentage =  sprintf ( "%.3f", 100.0*($FTN{returned}/$FTN{total}) );
  print "<tr><td align='center'><font color='green'>Returned</font></td><td align='center'><font color='green'>$FTN{returned}</font></td><td align='center'><font color='green'>$percentage %</font></td></tr>";
  
  # Incomplete
  $percentage =  sprintf ( "%.3f", 100.0*($FTN{incomplete}/$FTN{total}) );
  print "<tr><td align='center'><font color='orange'>Incomplete</font></td><td align='center'><font color='orange'>$FTN{incomplete}</font></td><td align='center'><font color='orange'>$percentage %</font></td></tr>";
  
  # Expired
  $percentage =  sprintf ( "%.3f", 100.0*($FTN{expired}/$FTN{total}) );
  print "<tr><td align='center'><font color='orange'>Expired</font></td><td align='center'><font color='orange'>$FTN{expired}</font></td><td align='center'><font color='orange'>$percentage %</font></td></tr>";
  
  # Failed
  $percentage =  sprintf ( "%.3f", 100.0*($FTN{failed}/$FTN{total}) );
  print "<tr><td align='center'><font color='red'>Failed</font></td><td align='center'><font color='red'>$FTN{failed}</font></td><td align='center'><font color='red'>$percentage %</font></td></tr>";
  
  # Failed
  $percentage =  sprintf ( "%.3f", 100.0*($FTN{noresponse}/$FTN{total}) );
  print "<tr><td align='center'><font color='red'>No Response</font></td><td align='center'><font color='red'>$FTN{noresponse}</font></td><td align='center'><font color='red'>$percentage %</font></td></tr>";
                   
  # Total
  $percentage =  sprintf ( "%.3f", 100.0*($FTN{total}/$FTN{total}) );
  print "<tr><td align='center'><font color='grey'>Total</font></td><td align='center'><font color='grey'>$FTN{total}</font></td><td align='center'><font color='grey'>$percentage %</font></td></tr>";
          
  # FTS
  print "<tr><th colspan='3'>FTS</th></tr>";
  
  # Queued
  $percentage =  sprintf ( "%.3f", 100.0*($FTS{queued}/$FTS{total}) );
  print "<tr><td align='center'><font color='green'>Queued</font></td><td align='center'><font color='green'>$FTS{queued}</font></td><td align='center'><font color='green'>$percentage %</font></td></tr>";
  
  # Returned
  $percentage =  sprintf ( "%.3f", 100.0*($FTS{returned}/$FTS{total}) );
  print "<tr><td align='center'><font color='green'>Returned</font></td><td align='center'><font color='green'>$FTS{returned}</font></td><td align='center'><font color='green'>$percentage %</font></td></tr>";
  
  # Incomplete
  $percentage =  sprintf ( "%.3f", 100.0*($FTS{incomplete}/$FTS{total}) );
  print "<tr><td align='center'><font color='orange'>Incomplete</font></td><td align='center'><font color='orange'>$FTS{incomplete}</font></td><td align='center'><font color='orange'>$percentage %</font></td></tr>";
  
  # Expired
  $percentage =  sprintf ( "%.3f", 100.0*($FTS{expired}/$FTS{total}) );
  print "<tr><td align='center'><font color='orange'>Expired</font></td><td align='center'><font color='orange'>$FTS{expired}</font></td><td align='center'><font color='orange'>$percentage %</font></td></tr>";
  
  # Failed
  $percentage =  sprintf ( "%.3f", 100.0*($FTS{failed}/$FTS{total}) );
  print "<tr><td align='center'><font color='red'>Failed</font></td><td align='center'><font color='red'>$FTS{failed}</font></td><td align='center'><font color='red'>$percentage %</font></td></tr>";
  
  # Failed
  $percentage =  sprintf ( "%.3f", 100.0*($FTS{noresponse}/$FTS{total}) );
  print "<tr><td align='center'><font color='red'>No Response</font></td><td align='center'><font color='red'>$FTS{noresponse}</font></td><td align='center'><font color='red'>$percentage %</font></td></tr>";
                   
  # Total
  $percentage =  sprintf ( "%.3f", 100.0*($FTS{total}/$FTS{total}) );
  print "<tr><td align='center'><font color='grey'>Total</font></td><td align='center'><font color='grey'>$FTS{total}</font></td><td align='center'><font color='grey'>$percentage %</font></td></tr>";


  print "</table>";
  
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
     eval { $end_dt = $iso8601->parse_datetime( $end ); };
     if ( $@ ) {
         print "<br><font color='red'><strong>ERROR: $@, dates are '$start' and '$end'</strong></font><br>";
         return -1;
     }	 
     $end_dt->add( days => 1 );
     
     my $current_dt = $iso8601->parse_datetime( $current );
     my $interval = DateTime->compare($current_dt, $end_dt);
     
     return $interval;

  }
