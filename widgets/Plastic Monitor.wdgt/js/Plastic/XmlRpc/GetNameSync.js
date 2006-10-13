var getNameSync = {

   // creates an XMLHttpRequest instance
   createXmlHttpRequestObject: function() 
   {
     // will store the reference to the XMLHttpRequest object
     var xmlHttp;
     // this should work for all browsers except IE6 and older
     try
     {
       // try to create XMLHttpRequest object
       xmlHttp = new XMLHttpRequest();
     }
     catch(e)
     {
  
     }
     // return the created object or display an error message
     if (!xmlHttp)
       alert("Error creating the XMLHttpRequest object.");
     else 
       return xmlHttp;
   },

   // the function handles that handles updating the document
   makeRequest: function( $plid )
   {
      if(window.console) {
         window.console.log("Called getNameSync.makeRequest()");
      }

      var XmlRpc = new XMLRPCMessage(["plastic.hub.requestToSubset"]);
      var sender = "widget://com.apple.widget.PlasticMonitor/";
      XmlRpc.addParameter(sender);
      var message = "ivo://votech.org/info/getName"; 
      XmlRpc.addParameter(message);
      var args = [ ];
      XmlRpc.addParameter( args );
      var recipientids = [ $plid ];
      XmlRpc.addParameter( recipientids );
  
      var message = XmlRpc.xml();
      

      xmlHttp['nameSync'] = getNameSync.createXmlHttpRequestObject(); 
      var serverAddress = plastic.xmlrpcEndpoint();

      // only continue if xmlHttp['nameSync'] isn't void
      if (xmlHttp['nameSync'])
      {
  
        // try to connect to the server
        try
        {
          // continue only if the XMLHttpRequest object isn't busy
          // and the cache is not empty
          if ( xmlHttp['nameSync'].readyState == 4 ||
	       xmlHttp['nameSync'].readyState == 0 )
          {
 
            xmlHttp['nameSync'].open("POST", serverAddress, false);
            xmlHttp['nameSync'].setRequestHeader("Content-Type", "text/xml");
            xmlHttp['nameSync'].send( '<?xml version="1.0"?>' + message);
          }
        }
        catch (e)
        {
          // display an error when failing to connect to the server
          alert(e.toString());
        }
    
        var response ="ERROR";
        try
          {
            // read the response from the server

            //response = xmlHttp['nameSync'].responseText;
            response = xmlHttp['nameSync'].responseXML;
	    
            // server error?
           if (response.indexOf("ERRNO") >= 0 
             || response.indexOf("error:") >= 0
             || response.length == 0)
           throw(response.length == 0 ? "Server error." : response);
  
          }
          catch(e)
          {
        
            // display error message
            // display error message
            if( window.console) {
               window.console.log( 
	           "Error: response = xmlHttp['nameSync'].response;" );
               window.console.log( "Error: " + e.toString() );
            }
            alert(e.toString());
          }
      
	  //response = response.replace( /</g, "&lt;" );
	  //response = response.replace( />/g, "&gt;<br>" );
	  //statusDiv = document.getElementById( 'selectedName' );
          //statusDiv.innerHTML = "<pre>" + response +"</pre>";
          //return response;
	  
	  var plasticName =
	     response.getElementsByTagName("value")[1].firstChild.nodeValue;
          return plasticName;
	  
	  
      }      
    
   }

}
