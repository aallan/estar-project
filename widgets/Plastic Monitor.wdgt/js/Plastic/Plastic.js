var plastic = {

/* General functions */

isHubRunning: function() {

   var hubStatus = 0;
   if( window.widget ) {   
 
      var theLocation = plastic.getFileLocation();
      var isPresent = widget.system("/bin/test -f " + theLocation, null).status;
      if ( isPresent == 0 ) {
         hubStatus = 1;
      }
   }
   return hubStatus;  /* returns 1 if hub is running */
},

plasticVersion: function() {

  var version = "";
  if ( window.widget ) {
     var string = plastic.readPlasticFile();
     var lines = string.split("\n" );
     for ( var i in lines ) {
        if ( /plastic.version/.test(lines[i]) ) {
           var values = lines[i].split( "=" );
	   version = values[1];
           break;
        }
     }
  }
  return version;

},

/* Get endpoints */

xmlrpcEndpoint: function() {

  var endpoint = "";
  if ( window.widget ) {
     var string = plastic.readPlasticFile();
     var lines = string.split("\n" );
     for ( var i in lines ) {
        if ( /plastic.xmlrpc.url/.test(lines[i]) ) {
           var values = lines[i].split( "=" );
	   endpoint = values[1];
	   endpoint = endpoint.replace( /\\/g, "" );
           break;
        }
     }  
  
  }
  return endpoint;

},

httpEndpoint: function() {

  var endpoint = "";
  if ( window.widget ) {
     var string = plastic.readPlasticFile();
     endpoint = plastic.xmlrpcEndpoint();
     endpoint = endpoint.replace( /xmlrpc/, "" );
  }
  return endpoint;

},


/* Utility routines */

getUser: function() {

   var userName = "";
   if( window.widget ) {   
      userName = widget.system( '/usr/bin/id -un', null ).outputString;
      userName = userName.replace( /^\s*/, "" );
      userName = userName.replace( /\s*$/, "" );  
   }
   return userName;
},

getFileLocation: function() {

   var fileLocation = "";
   if ( window.widget ) {
      var userName = plastic.getUser();
      fileLocation = "/Users/" + userName + "/.plastic";
   }
   return fileLocation;
   
},

readPlasticFile: function() {

   var plasticFile = "";
   if( window.widget ) {   
      var theLocation = plastic.getFileLocation();
      plasticFile = widget.system("/bin/cat "+theLocation,null).outputString;
   }
   return plasticFile; /* returns string with file contents */
   
}

}
