          var debugMode = false;

          // Write to the debug div when in Safari.
          // Send a simple alert to Console when in Dashboard.
          function debug(str) {
               if (debugMode) {
                    if (window.widget) {
                         alert(str);
                    } else {
                         var debugDiv = document.getElementById('debugDiv');
                         debugDiv.appendChild(document.createTextNode(str));
                         debugDiv.appendChild(document.createElement("br"));
                         debugDiv.scrollTop = debugDiv.scrollHeight;
                    }
               }
          }

          // Toggle the debugMode flag, but only show the debugDiv in Safari
          function toggleDebug() {
               debugMode = !debugMode;
               if (debugMode == true && !window.widget) {
                    document.getElementById('debugDiv').style.display = 'block';
               } else {
                    document.getElementById('debugDiv').style.display = 'none';
               }
          }
