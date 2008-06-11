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
  print "Content-type: text/ascii\n\n"; 
	
  #foreach my $i ( 0 ... $#sorted ) {
  #  print "$i $sorted[$i]<br>";
  #}  

  my $serialised;
  if ( defined $query{file} ) {
 
     my $skipped = 0;
     my $count = 0;
     foreach my $i ( 0 ... $#files ) {
     
        #print "\n$i $files[$i] ";
	if ( $files[$i] =~ m/\./ || $files[$i] =~ m/\.\./ ||
             $files[$i] =~ m/^\d{4}$/ || $files[$i] =~ m/^\d{2}-\d{4}$/ ) {
           $skipped = $skipped + 1;
	   #print "skipping ($skipped)";
	   next;
	}   	   
	
	$count = $count + 1;
        if ( $count == $query{file} ) {
	      #print "final file count = $count, skipped = $skipped";
	      $serialised = $files[$i];
	      last;
	}   
	#print "ok ($count)"; 

      }
      
     #print " serialised = $serialised\n";	  
  } elsif ( defined $query{id} ) {
      $serialised = $query{id};
  }
  
  print $serialised;
  my $object;
  eval { $object = thaw( $dir, $serialised ); };

  my $status = $object->status();
  my $node = $object->node();
  my ($node_name, $score_reply) = $object->highest_score();
  $node = "FTN" if $node eq "estar3.astro.ex.ac.uk:8077";
  $node = "FTN" if $node eq "132.160.98.239:8080/axis/services/NodeAgent";
  $node = "LT" if $node eq "estar3.astro.ex.ac.uk:8078";
  $node = "LT" if $node eq "161.72.57.3:8080/axis/services/NodeAgent";
  $node = "LT" if $node eq "161.72.57.3:8080/org_estar_nodeagent/services/NodeAgent";
  $node = "FTS" if $node eq "estar3.astro.ex.ac.uk:8079";  
  $node = "FTS" if $node eq "150.203.153.202:8080/axis/services/NodeAgent";
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
     $time[0] =~ s/UTC/\+0000/ if $time[0] =~ "UTC";
     $time[1] =~ s/UTC/\+0000/ if $time[1] =~ "UTC";	  
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
   	   
   print " $target $full_name";

   # TARGET TYPE - 2 ----------------------------------------------
	
   if ( $group_count == 3 && $exposure == 30 && $target =~ m/OB\d{5}/ ||
   	!defined $series_count && !defined $group_count && $exposure == 90 && $target =~ m/OB\d{5}/ ) {

      print " event";

   } elsif ( $target =~ m/ESSENCE/ ) {

      print " event";

   } else {
      if ( $type eq 'toop' ) {
   	 print " override"; 
      } else {
   	 print " $type"; 
      }
   }  

   # PRIORITY - 3 -----------------------------------------------------

   print " $priority";

   # TIMESTAMP - 4 ------------------------------------------------
	
   print " $time[0] $time[1]";
	  
  # EXPOSURE - 5 ----------------------------------------------  

  $series_count = 0 unless defined $series_count;
  $group_count = 0 unless defined $group_count;
  print " $series_count $group_count $exposure";
	
  # FILTER - 6 -----------------------------------------------------
  
  print " $filter";

  # NODE - 7 ---------------------------------------------------------
  if ( defined $node ) {
     print " $node";
  } else {
     print " UNKNOWN";
  }      

  # STATUS - 8 ---------------------------------------------------

  my $expire;
  my $parse_error = 0;
  eval { $expire = expired( @time ); };
  if( $@ ) {
      $parse_error = 1;    
  }
  
  if ( $status eq "running" ) {
     if ( $expire == -1 || $expire == 0 ) {
  	print " queued";
     } else {	
  	print " no_response";
     }

  } elsif ( $parse_error == 1 ) {
     my @updates = $object->update();
     my $num = scalar @updates;
     print " error";
     print "($num)" if $num > 0;
     
  } elsif ( $status eq "failed" ) {
     print " failed";
     
  } elsif ( $status eq "update" ) {
     my @updates = $object->update();
     my $num = scalar @updates;
     if( $expire == -1 || $expire == 0 ) {
  	 print " in_progress";
  	 print "($num)" if $num > 0;
     } else {
  	 print " expired";
  	 print "($num)" if $num > 0;
     }
     
  } elsif ( $status eq "incomplete" ) {
     my @updates = $object->update();
     my $num = scalar @updates;
     print " incomplete";
     print "($num)" if $num > 0;

  } elsif ( $status eq "returned" ) {
     my @updates = $object->update();
     my $num = scalar @updates;
     print " returned";
     print "($num)" if $num > 0;
     
  } else {
     print " $status";
  }  

  if ( defined $project ) {
     print " $project";
  } else {
     print " unknown";
  }

  # RA & Dec

  $ra =~ s/ /:/g;
  $dec =~ s/ /:/g; 
  print " $ra $dec"; 
  exit;
  
# S U B - R O U T I N E S #################################################
 
  sub error {
    my $error = shift;
  
    print "Content-type: text/ascii\n\n";       
    print "Error: $error";
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
