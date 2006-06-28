package Search;
  
  sub search {  
    my $class = shift;
    my $ra = shift;
    my $dec = shift;
    my $name = shift;
    my $radius = shift;
    my $equinox = shift;
    my $catalog = shift;
    my $format = shift;
    
    # validate data
    $radius = 10 unless defined $radius;
    $equinox = "J2000" unless defined $equinox;

    # polymorphically select the catalogue query
    my $module = "Astro::Catalog::Query::$catalog";
    
    # build the query
    my $query;

    # RA & Dec 
    if ( defined $ra && defined $dec ) {
       
       # need to specify 'colour' for SuperCOS and an increased timeout
       if ( $query{catalogue} eq "SuperCOSMOS" ) {
   
          $query = new $module( RA      => $ra, 
                                Dec     => $dec,
                                Equinox => $equinox,
                                Radius  => $radius,
                                Colour  => 'UKJ',
                                Timeout => 60 );
                                
       # otherwise don't...                       
       } else {
          $query = new $module( RA      => $ra, 
                                Dec     => $dec,
                                Equinox => $equinox,
                                Radius  => $radius ); 
       }  
     
    # Target                     
    } elsif ( defined $name ) {
 
       # resolve target using Sesame
       my $sesame_query = new Astro::Catalog::Query::Sesame( 
                                            Target => $name );
       my $sesame_result; 
       eval { $sesame_result = $sesame_query->querydb(); };
       if ( $@ ) {
 
          # failed, fallback to SIMBAD
          my $simbad_query = new Astro::SIMBAD::Query( Target  => $name,
                                                       Timeout => 5 );
                          
          my $simbad_result;
          eval { $simbad_result = $simbad_query->querydb(); };
          if ( $@ ) {      
             die SOAP::Fault
                ->faultcode("Server.NetworkError")
                ->faultstring( "Server Error: Unable to contact CDS Sesame " .
                               " or CDS SIMBAD for name resolution.");
          }
          
          if ( defined $simbad_result ) {   
             my @object = $simbad_result->objects( );
             if ( defined $object[0] ){
                $ra = $object[0]->ra();
                $dec = $object[0]->dec();    
             } 
          } else {
              die SOAP::Fault
                ->faultcode("Server.ResolutionError")
                ->faultstring( "Server Error: Unable to resolve target '" . 
                               $name . "' using the CDS SIMBAD service.");      
          }              
                               
       } else {
      
          unless ( defined $sesame_result ) {
             die SOAP::Fault
                ->faultcode("Server.ResolutionError")
                ->faultstring( "Server Error: Unable to resolve target '" . 
                               $name . "' using the CDS Sesame service.");
          }
          my $star = $sesame_result->popstar();
          $ra = $star->ra();
          $dec = $star->dec();  
       }
 
       # this should only happen if we have an unresolved target, right?
       if ( $dec == 0 ) {
          die SOAP::Fault
             ->faultcode("Server.UnkownError")
             ->faultstring( "Server Error: Unable to resolve target '" . 
                            $name . "' using either Sesame or SIMBAD.");
       }              
      
       # need to specify 'colour' for SuperCOS and an increased timeout
       if ( $catalog eq "SuperCOSMOS" ) {
   
          $query = new $module( RA      => $ra, 
                                Dec     => $dec,
                                Equinox => $equinox,
                                Radius  => $radius,
                                Colour  => 'UKJ',
                                Timeout => 60 );
                                
       # otherwise don't...                       
       } else {
          $query = new $module( RA      => $ra, 
                                Dec     => $dec,
                                Equinox => $equinox,
                                Radius  => $radius ); 
       }    
          
    } else {
       die SOAP::Fault
          ->faultcode("Server.QueryError")
          ->faultstring( "Server Error: Unable to build a query. " .
                         "RA, Dec and target name are all undefined." );
    }
    
 
    # grab the catalogue
    my $catalog;

    eval { $catalog = $query->querydb(); };
    if ( $@ ) {
       die SOAP::Fault
          ->faultcode("Server.CatalogError")
          ->faultstring( "Server Error: Unable to make a remote query. $@" );
    }   
     
    # write to the buffer
    my $buffer;
    eval { $catalog->write_catalog( 
                           Format => $format, File => \$buffer ); };
    if ( $@ ) {
       die SOAP::Fault
          ->faultcode("Server.WriteError")
          ->faultstring( "Server Error: Unable to serialise catalogue. $@" );
    }    
    
    return "$buffer\n";
      
  }

1;
