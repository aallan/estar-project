var getDescription = {


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
         window.console.log("Called getDescription.makeRequest()");
      }

      var XmlRpc = new XMLRPCMessage(["plastic.hub.requestToSubset"]);
      var sender = "widget://com.apple.widget.PlasticMonitor/";
      XmlRpc.addParameter(sender);
      var message = "ivo://votech.org/info/getDescription"; 
      XmlRpc.addParameter(message);
      var args = [ ];
      XmlRpc.addParameter( args );
      var recipientids = [ $plid ];
      XmlRpc.addParameter( recipientids );
  
      var message = XmlRpc.xml();
      

      xmlHttp['description'] = getDescription.createXmlHttpRequestObject(); 
      var serverAddress = plastic.xmlrpcEndpoint();

      // only continue if xmlHttp['description'] isn't void
      if (xmlHttp['description'])
      {
  
        // try to connect to the server
        try
        {
          // continue only if the XMLHttpRequest object isn't busy
          // and the cache is not empty
          if ( xmlHttp['description'].readyState == 4 ||
	       xmlHttp['description'].readyState == 0 )
          {
 
            xmlHttp['description'].open("POST", serverAddress, true);
            xmlHttp['description'].setRequestHeader("Content-Type", "text/xml");
            xmlHttp['description'].onreadystatechange =
	                            getDescription.handleRequestStateChange;
            xmlHttp['description'].send( '<?xml version="1.0"?>' + message);
	   
          }
        }
        catch (e)
        {
          // display an error when failing to connect to the server
          alert(e.toString());
        }
     }
   },	
	

   // function that handles the HTTP response
   handleRequestStateChange: function() 
   {
     
     if(window.console) {
           window.console.log("Called getDescription.handleReqestStateChange(" +
	                   xmlHttp['description'].readyState + ")");
     }

   // when readyState is 4, we read the server response
   if (xmlHttp['description'].readyState == 4) 
   {
      // continue only if HTTP status is "OK"
      if (xmlHttp['description'].status == 200) 
      {
        try
        {
          // read the response from the server
          getDescription.readResponse();
        }
        catch(e)
        {
          // display error message
          alert(e.toString());
        }
      }
      else
      {
        // display error message
        alert(xmlHttp['description'].statusText);
      }
    }
  },

  // read server's response 
  readResponse: function()
  {

    if ( window.console ) {
      window.console.log("Called getDescription.readResponse()");
    }

    // retrieve the server's response 
    var response;
    try 
    {
       //response = xmlHttp['description'].responseText;
       response = xmlHttp['description'].responseXML;
    }
    catch(e)
    {
        // display error message
        if( window.console) {
           window.console.log(
	     "Error: response = xmlHttp['description'].response;" );
           window.console.log( "Error: " + e.toString() );
        }
        alert(e.toString());
    }

    //if(window.console) {
    //      window.console.log( response );
    //}

    // server error?
    //if (response.indexOf("ERRNO") >= 0 || 
    //    response.indexOf("error:") >= 0 || response.length == 0) {
    //  throw(response.length == 0 ? "Server error." : response);
    //}
   
    //response = response.replace( /</g, "&lt;" );
    //response = response.replace( />/g, "&gt;<br>" );
    //div = document.getElementById( 'selectedName' );
    //div.innerHTML = "<pre>" + response +"</pre>"; 
   
    var plasticDescription = 
        response.getElementsByTagName("value")[1].firstChild.nodeValue;
    descriptionDiv = document.getElementById( 'selectedDescription' );
    descriptionDiv.innerHTML = plasticDescription;  
	  
    scrollArea.refresh();
    scrollBar.refresh();		  
	  
   }      
    
}


