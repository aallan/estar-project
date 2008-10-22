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

  my $month = localtime->mon() + 1;
  $month = "0$month" if $month < 10;
  $this_year =~ s/\?dir=$month-2008//;
  #print $this_year;
  
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

  foreach my $i ( 0 ... $#files ) {
#  for ( my $i = $#files; $i >= 0; $i = $i - 1 ) {
   
     #print "'".$files[$i]."'\n";
     next if $files[$i] =~ m/\./;
     next if $files[$i] =~ m/\.\./;
     next if $files[$i] =~ m/^\d{4}$/;
     next if $files[$i] =~ m/^\d{2}-\d{4}$/;
     
     #print "<tr>";
     #print "<td><font color='grey'>$files[$i]</font></td>";
     my $object;
     eval { $object = thaw( $dir, $files[$i] ); };
     
     # QUERY OBSERVATION OBJECT ------------------------------------------
     if ( $@ ) {
        #print "<font color='red'>Error opening $files[$i]: $@</font>\n";
    } else {
        #print "<td><font color='green'>OK</font></td>\n";
	
	my $status = $object->status();
	my $node = $object->node();
        my ($node_name, $score_reply) = $object->highest_score();
	$node = "FTN" if $node eq "estar3.astro.ex.ac.uk:8077";
	$node = "FTN Proxy" if $node eq "132.160.98.239:8080/axis/services/NodeAgent";
	$node = "FTN New" if $node eq "132.160.98.239:8080/org_estar_nodeagent/services/NodeAgent";
	$node = "LT" if $node eq "estar3.astro.ex.ac.uk:8078";
	$node = "LT Proxy" if $node eq "161.72.57.3:8080/axis/services/NodeAgent";
	$node = "LT New" if $node eq "161.72.57.3:8080/org_estar_nodeagent/services/NodeAgent";
	$node = "FTS" if $node eq "estar3.astro.ex.ac.uk:8079";  
	$node = "FTS Proxy" if $node eq "150.203.153.202:8080/axis/services/NodeAgent";
	$node = "FTS New" if $node eq "150.203.153.202:8080/org_estar_nodeagent/services/NodeAgent";
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
	  $time[0] =~ s/UTC/\+0000/ if $time[0] =~ "UTC";
	  $time[1] =~ s/UTC/\+0000/ if $time[1] =~ "UTC";	  
          $type = $obs->targettype();
          $filter = $obs->filter();
          $priority = $obs->priority();
          $project = $obs->project() if $obs->isa("XML::Document::RTML");
          #print "\$obs->isa() = " . $obs->isa("XML::Document::RTML") . ", $project is" . $obs->project() . "<br>";
        }

        my $expire = expired( @time );
	
        # LT ---------------------------------------------------
       
        if ($node eq "LT" || $node eq "LT Proxy" || $node eq "LT New") {
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
  

  # NB: first 2 entries in a directory listing are '.' and '..'
  print "Content-type: text/ascii\n\n"; 
  
  # Data
  my $too_big = 1;
  my $chart_queued = $LT{queued};
  my $chart_returned = $LT{returned};
  my $chart_incomplete = $LT{incomplete};
  my $chart_expired = $LT{expired};
  my $chart_failed = $LT{failed};
  my $chart_no_reply = $LT{noresponse};

  while ( $too_big ) {
    if ( $chart_queued > 100.0 || $chart_returned > 100.0 ||
         $chart_incomplete > 100.0 || $chart_expired > 100.0 ||
         $chart_failed > 100.0 || $chart_no_reply > 100.0 ) {

      $chart_queued = $chart_queued / 2;
      $chart_returned = $chart_returned / 2;
      $chart_incomplete = $chart_incomplete / 2;
      $chart_expired = $chart_expried / 2;
      $chart_failed = $chart_failed / 2;
      $chart_no_reply = $chart_no_reply / 2;
    } else {
      $too_big = 0;
    }
  }

  my $LT_data = "$chart_queued,$chart_returned,$chart_incomplete,$chart_expired,$chart_failed,$chart_no_reply";

  $too_big = 1;
  $chart_queued = $FTN{queued};
  $chart_returned = $FTN{returned};
  $chart_incomplete = $FTN{incomplete};
  $chart_expired = $FTN{expired};
  $chart_failed = $FTN{failed};
  $chart_no_reply = $FTN{noresponse};

  while ( $too_big ) {
    if ( $chart_queued > 100.0 || $chart_returned > 100.0 ||
         $chart_incomplete > 100.0 || $chart_expired > 100.0 ||
         $chart_failed > 100.0 || $chart_no_reply > 100.0 ) {

      $chart_queued = $chart_queued / 2;
      $chart_returned = $chart_returned / 2;
      $chart_incomplete = $chart_incomplete / 2;
      $chart_expired = $chart_expried / 2;
      $chart_failed = $chart_failed / 2;
      $chart_no_reply = $chart_no_reply / 2;
    } else {
      $too_big = 0;
    }
  }

  my $FTN_data = "$chart_queued,$chart_returned,$chart_incomplete,$chart_expired,$chart_failed,$chart_no_reply";

  $too_big = 1;
  $chart_queued = $FTS{queued};
  $chart_returned = $FTS{returned};
  $chart_incomplete = $FTS{incomplete};
  $chart_expired = $FTS{expired};
  $chart_failed = $FTS{failed};
  $chart_no_reply = $FTS{noresponse};

  while ( $too_big ) {
    if ( $chart_queued > 100.0 || $chart_returned > 100.0 ||
         $chart_incomplete > 100.0 || $chart_expired > 100.0 ||
         $chart_failed > 100.0 || $chart_no_reply > 100.0 ) {

      $chart_queued = $chart_queued / 2;
      $chart_returned = $chart_returned / 2;
      $chart_incomplete = $chart_incomplete / 2;
      $chart_expired = $chart_expried / 2;
      $chart_failed = $chart_failed / 2;
      $chart_no_reply = $chart_no_reply / 2;
    } else {
      $too_big = 0;
    }
  }

  my $FTS_data = "$chart_queued,$chart_returned,$chart_incomplete,$chart_expired,$chart_failed,$chart_no_reply";
 
  my $url_head = 'http://chart.apis.google.com/chart?cht=p&chco=0000ff&chd=t:';
  my $url_foot = '&chs=360x200&chl=Queued|Returned|Incomplete|Expired|Failed|No%20Response';
  print "$LT{total},$LT{queued},$LT{returned},$LT{incomplete},$LT{expired},$LT{failed},$LT{noresponse}\n";
  print "$url_head$LT_data$url_foot\n";
  print "$FTN{total},$FTN{queued},$FTN{returned},$FTN{incomplete},$FTN{expired},$FTN{failed},$FTN{noresponse}\n";
  print "$url_head$FTN_data$url_foot\n"; 
  print "$FTS{total},$FTS{queued},$FTS{returned},$FTS{incomplete},$FTS{expired},$FTS{failed},$FTS{noresponse}\n";
  print "$url_head$FTS_data$url_foot\n";
   
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
        if ( $@ =~ /The 'hour' parameter \("24"\)/ ) {
           $end =~ s/T24/T00/;
           eval { $end_dt = $iso8601->parse_datetime( $end ); };
           if ( $@ ) {
              #print "Content-type: text/ascii\n\nERROR: $@, dates are '$start' and '$end'";
              return -1;
           }
         } else {
            #print "Content-type: text/ascii\n\nERROR: $@, dates are '$start' and '$end'";
            return -1;
         }
     }	 
     $end_dt->add( days => 1 );
     
     my $current_dt = $iso8601->parse_datetime( $current );
     my $interval = DateTime->compare($current_dt, $end_dt);
     
     return $interval;

  }
