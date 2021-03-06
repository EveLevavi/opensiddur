xquery version "3.0";
(: Transliteration API module
 : 
 : Functions assume that the following has already been done:
 :  authentication,
 :  content negotiation
 : 
 : Copyright 2012-2013 Efraim Feinstein <efraim@opensiddur.org>
 : Open Siddur Project
 : Licensed Under the GNU Lesser General Public License, version 3 or later
 :)
module namespace tran = 'http://jewishliturgy.org/api/transliteration';

import module namespace crest="http://jewishliturgy.org/modules/common-rest"
  at "/db/code/api/modules/common-rest.xqm";
import module namespace data="http://jewishliturgy.org/modules/data"
  at "/db/code/api/modules/data.xqm";

declare namespace tr="http://jewishliturgy.org/ns/tr/1.0";

declare namespace output="http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace error="http://jewishliturgy.org/errors";

declare variable $tran:data-type := "transliteration";
declare variable $tran:schema := "/db/schema/transliteration.rnc";
declare variable $tran:schematron := "/db/schema/transliteration.xsl2";
declare variable $tran:path-base := concat($data:path-base, "/", $tran:data-type);
declare variable $tran:api-path-base := concat("/api/data/", $tran:data-type);

declare function tran:validate(
  $tr as item(),
  $old-doc as document-node()?
  ) as xs:boolean {
  crest:validate($tr, $old-doc, 
    xs:anyURI($tran:schema), xs:anyURI($tran:schematron), ())
};

declare function tran:validate-report(
  $tr as item(),
  $old-doc as document-node()?
  ) as element() {
  crest:validate-report(
    $tr, $old-doc, 
    xs:anyURI($tran:schema), xs:anyURI($tran:schematron), ()
  )
};

declare 
  %rest:GET
  %rest:path("/api/data/transliteration/{$name}")
  %rest:produces("application/xml")
  function tran:get(
    $name as xs:string
  ) as item()+ {
  crest:get($tran:data-type, $name)
};

(:~ Discovery and query API: 
 : list accessible transliterations 
 : or search
 :)
declare 
  %rest:GET
  %rest:path("/api/data/transliteration")
  %rest:query-param("q", "{$q}", "")
  %rest:query-param("start", "{$start}", 1)
  %rest:query-param("max-results", "{$max-results}", 100)
  %rest:produces("application/xhtml+xml", "application/xml", "text/html", "text/xml")
  %output:method("html5")
  function tran:list(
    $q as xs:string*,
    $start as xs:integer*,
    $max-results as xs:integer*
  ) as item()+ {
  crest:list($q, $start, $max-results,
    "Transliteration API", $tran:api-path-base,
    tran:query-function#1, tran:list-function#0,
    <crest:additional text="access" relative-uri="access"/>, 
    tran:title-function#1
  )
};

(: @return (list, start, count, n-results) :) 
declare function tran:query-function(
    $query as xs:string
  ) as element()* {
  for $doc in collection($tran:path-base)//(tr:title|tr:description)
        [ft:query(.,$query)]
  order by $doc//tr:title ascending
  return $doc
};

declare function tran:list-function(
  ) as element()* {
  for $doc in collection($tran:path-base)/tr:schema
  order by $doc//tr:title ascending
  return $doc
};

declare function tran:title-function(
  $doc as document-node()
  ) as xs:string {
  $doc//tr:title[1]/string()
};

declare 
  %rest:DELETE
  %rest:path("/api/data/transliteration/{$name}")
  function tran:delete(
    $name as xs:string
  ) as item()+ {
  crest:delete($tran:data-type, $name)
};

declare
  %rest:POST("{$body}")
  %rest:path("/api/data/transliteration")
  %rest:consumes("application/xml", "text/xml")
  function tran:post(
    $body as document-node()
  ) as item()+ {
  crest:post(
    $tran:data-type,
    $tran:path-base,
    $tran:api-path-base,
    $body,
    tran:validate#2,
    tran:validate-report#2,
    tran:title-function#1
  )    
};

declare
  %rest:PUT("{$body}")
  %rest:path("/api/data/transliteration/{$name}")
  %rest:consumes("application/xml", "text/xml")
  function tran:put(
    $name as xs:string,
    $body as document-node()
  ) as item()+ {
  crest:put(
    $tran:data-type, $name, $body,
    tran:validate#2,
    tran:validate-report#2
  )
};

declare 
  %rest:GET
  %rest:path("/api/data/transliteration/{$name}/access")
  %rest:produces("application/xml")
  function tran:get-access(
    $name as xs:string
  ) as item()+ {
  crest:get-access($tran:data-type, $name)
};

declare 
  %rest:PUT("{$body}")
  %rest:path("/api/data/transliteration/{$name}/access")
  %rest:consumes("application/xml", "text/xml")
  function tran:put-access(
    $name as xs:string,
    $body as document-node()
  ) as item()+ {
  crest:put-access($tran:data-type, $name, $body)
};
