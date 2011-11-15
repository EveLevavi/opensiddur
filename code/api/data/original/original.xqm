xquery version "1.0";
(: API for POSTing new resources to original
 : 
 : A title must be provided		
 :
 : Open Siddur Project
 : Copyright 2011 Efraim Feinstein <efraim@opensiddur.org>
 : Licensed under the GNU Lesser General Public License, version 3 or later
 :
 :)
module namespace orig="http://jewishliturgy.org/api/data/original";

import module namespace api="http://jewishliturgy.org/modules/api"
	at "/code/api/modules/api.xqm";
import module namespace app="http://jewishliturgy.org/modules/app"
	at "/code/modules/app.xqm";
import module namespace nav="http://jewishliturgy.org/modules/nav"
  at "/code/api/modules/nav.xqm";

declare default element namespace "http://www.w3.org/1999/xhtml"; 
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace err="http://jewishliturgy.org/errors";

declare variable $orig:allowed-methods := ("GET", "POST");
declare variable $orig:accept-content-type := (
  api:xml-content-type(),
  api:tei-content-type()
  );
declare variable $orig:request-content-type := (
  api:tei-content-type(),
  api:xml-content-type()
  );

declare function local:make-resource-name(
  $title as xs:string
  ) as xs:string {
  local:make-resource-name($title, 0)
};

declare function local:make-resource-name(
  $title as xs:string,
  $n as xs:integer
  ) as xs:string {
  let $proposed := concat(encode-for-uri($title),"_"[$n > 0],xs:string($n)[$n > 0], ".xml")
  return
    if (exists(collection("/group")[util:document-uri(.) = $proposed]))
    then local:make-resource-name($title, $n + 1)
    else $proposed
};


declare function orig:get() {
  doc("/code/api/data/resources/template.xml")
};

declare function orig:put() {
  local:disallowed()
};

declare function orig:post() {
  if (api:require-authentication())
  then
    let $user := app:auth-user()
    let $data := api:get-data()
    let $title := $data//tei:title[@type="main"]
    return 
      if (not($data instance of element(tei:TEI)
        or $data instance of element(tei:title)))
      then
        api:error(400, "You must post a valid JLPTEI document or a title")
      else if (empty($title))
      then 
        api:error(400, "The document must contain a tei:title element")
      else 
        (: TODO: real validation here! :)
        let $resource := local:make-resource-name(string($title[1]))
        let $collection := concat("/group/", $user)
        return
          if (xmldb:store($collection, $resource, 
            if ($data instance of element(tei:TEI))
            then $data
            else doc("/code/api/data/resources/template.xml")))
          then (
            xmldb:set-resource-permissions($collection, $resource,
              $user, $user, util:base-to-integer(0740, 8)),
            if ($data instance of element(tei:title))
            then 
              update replace doc(concat($collection, "/", $resource)//tei:title[@type="main"][1])
                with $title
            else (),
            response:set-status-code(201),
            response:set-header("Location", concat($uri, "/", replace($resource, "\.xml$", "")))
            )
          else 
            api:error(500, "Cannot store the resource. Internal error?", $resource)
  else 
    api:error((), "Authentication required")
};

declare function orig:delete() {
  local:disallowed()
};

declare function orig:go() {
  let $method := api:get-method()
  return
    if ($method = "GET")
    then orig:get()
    else if ($method = "PUT") 
    then orig:put()
    else if ($method = "POST")
    then orig:post()
    else if ($method = "DELETE")
    then orig:delete()
    else local:disallowed()
};
