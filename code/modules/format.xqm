(:~
 : XQuery functions to output a given XML file in a format.
 : 
 : Copyright 2011-2013 Efraim Feinstein <efraim.feinstein@gmail.com>
 : Open Siddur Project
 : Licensed under the GNU Lesser General Public License, version 3 or later
 :)
module namespace format="http://jewishliturgy.org/modules/format";

declare namespace exist="http://exist.sourceforge.net/NS/exist";
declare namespace error="http://jewishliturgy.org/errors";
declare namespace tr="http://jewishliturgy.org/ns/tr/1.0";

import module namespace app="http://jewishliturgy.org/modules/app" 
  at "xmldb:exist:///db/code/modules/app.xqm";
import module namespace mirror="http://jewishliturgy.org/modules/mirror" 
  at "xmldb:exist:///db/code/modules/mirror.xqm";
import module namespace paths="http://jewishliturgy.org/modules/paths" 
  at "xmldb:exist:///db/code/modules/paths.xqm";
import module namespace uri="http://jewishliturgy.org/transform/uri" 
  at "xmldb:exist:///db/code/modules/follow-uri.xqm";
import module namespace flatten="http://jewishliturgy.org/transform/flatten"
  at "xmldb:exist:///db/code/transforms/flatten/flatten.xqm";
import module namespace unflatten="http://jewishliturgy.org/transform/unflatten"
  at "xmldb:exist:///db/code/transforms/flatten/unflatten.xqm";
import module namespace combine="http://jewishliturgy.org/transform/combine"
  at "xmldb:exist:///db/code/transforms/flatten/combine.xqm";
import module namespace tohtml="http://jewishliturgy.org/transform/html"
  at "xmldb:exist:///db/code/transforms/tohtml.xqm";
  
declare variable $format:temp-dir := '.format';
declare variable $format:path-to-xslt := '/db/code/transforms';
declare variable $format:rest-path-to-xslt := app:concat-path($paths:internal-rest-prefix, $format:path-to-xslt);

declare variable $format:dependency-cache := "/db/cache/dependency";
declare variable $format:flatten-cache := "/db/cache/flatten";
declare variable $format:merge-cache := "/db/cache/merge";
declare variable $format:resolve-cache := "/db/cache/resolved";
declare variable $format:unflatten-cache := "/db/cache/unflattened";
declare variable $format:combine-cache := "/db/cache/combined";
declare variable $format:html-cache := "/db/cache/html";
declare variable $format:caches := (
    $format:dependency-cache,
    $format:flatten-cache,
    $format:merge-cache,
    $format:resolve-cache,
    $format:unflatten-cache,
    $format:combine-cache,
    $format:html-cache
    );

declare function local:wrap-document(
  $node as node()
  ) as document-node() {
  if ($node instance of document-node())
  then $node
  else document {$node}
};


(:~ setup to allow format functions to work :)
declare function format:setup(
  ) as empty-sequence() {
  for $collection in $format:caches
  where not(xmldb:collection-available($collection))
  return
    mirror:create($collection, "/db/data", true(),
      if ($collection = $format:html-cache)
      then map { "xml" := "html" }
      else map {}
    )
};

(:~ clear all format caches of a single file 
 : @param $path database path of the original resource
 :)
declare function format:clear-caches(
  $path as xs:string
  ) as empty-sequence() {
  for $cache in $format:caches
  where doc-available($path)
  return 
    let $doc := doc($path)
    return
      mirror:remove($cache, util:collection-name($doc), util:document-name($doc))
};

(:~ make a cached version of a flattened document,
 : and return it
 : @param $doc The document to flatten
 : @param $params Parameters to send to the transform
 : @param $original-doc The original document that was flattened 
 : @return The mirrored flattened document
 :) 
declare function format:flatten(
  $doc as document-node(),
  $params as map,
  $original-doc as document-node()
  ) as document-node() {
  let $flatten-transform := flatten:flatten-document(?, $params)
  return
    mirror:apply-if-outdated(
      $format:flatten-cache,
      $doc,
      $flatten-transform,
      $original-doc
    )
};

(:~ perform the transform up to the merge step 
 : @param $doc Original document
 : @param $params Parameters to pass to the transforms
 : @param $original-doc The original document that was merged 
 : @return The merged document (as an in-database copy)
 :)
declare function format:merge(
  $doc as document-node(),
  $params as map,
  $original-doc as document-node()
  ) as document-node() {
  let $merge-transform := flatten:merge-document(?, $params)
  return
    mirror:apply-if-outdated(
      $format:merge-cache,
      format:flatten($doc, $params, $original-doc),
      $merge-transform,
      $original-doc
    )
};

(:~ perform the transform up to the resolve-stream step 
 : @param $doc Original document
 : @param $params Parameters to pass to the transforms
 : @param $original-doc The original document that was resolved 
 : @return The merged document (as an in-database copy)
 :)
declare function format:resolve(
  $doc as document-node(),
  $params as map,
  $original-doc as document-node()
  ) as document-node() {
  let $resolve-transform := flatten:resolve-stream(?, $params)
  return
    mirror:apply-if-outdated(
      $format:resolve-cache,
      format:merge($doc, $params, $original-doc),
      $resolve-transform,
      $original-doc
    )
};

(:~ provide a display version of the flattened/merged hierachies  
 :)
declare function format:display-flat(
  $doc as document-node(),
  $params as map,
  $original-doc as document-node()
  ) as document-node() {
  flatten:display(
    format:resolve($doc, $params, $original-doc),
    $params
  )
};

(:~ perform the transform up to the unflatten step 
 : @param $doc Original document
 : @param $params Parameters to pass to the transforms
 : @param $original-doc The original document that was unflattened, if not $doc 
 : @return The unflattened document (as an in-database copy)
 :)
declare function format:unflatten(
  $doc as document-node(),
  $params as map,
  $original-doc as document-node()
  ) as document-node() {
  let $unflatten-transform := unflatten:unflatten-document(?, $params)
  return
    mirror:apply-if-outdated(
      $format:unflatten-cache,
      format:resolve($doc, $params, $original-doc),
      $unflatten-transform,
      $original-doc
    )
};

declare function format:get-dependencies(
  $doc as document-node()
  ) as document-node() {
  document {
    <format:dependencies>{
      for $dep in uri:dependency($doc, ())
      let $transformable := 
        matches($dep, "^/db/data/(original|tests)")
        (: TODO: add other transformables here... :)
      return 
        <format:dependency>{
          if ($transformable)
          then attribute transformable { $transformable }
          else (),
          $dep
        }</format:dependency>
    }</format:dependencies>
  }
};

(:~ set up an XML file containing all dependencies 
 : of a given document
 :)
declare function format:dependencies(
  $doc as document-node()
  ) as document-node() {
  mirror:apply-if-outdated(
    $format:dependency-cache,
    $doc,
    format:get-dependencies#1
  )
};

(:~ unflatten all transformable dependencies of a given document :)
declare function format:unflatten-dependencies(
  $doc as document-node(),
  $params as map
  ) as document-node()+ {
  for $dep in format:dependencies($doc)//format:dependency[@transformable]
  return format:unflatten(doc($dep), $params, doc($dep))
};
  
(:~ perform the transform up to the combine step 
 : @param $doc The document to be transformed
 : @param $params Parameters to pass to the transforms
 : @param $original-doc The original document that is being transformed (may be the same as $doc) 
 : @return The combined document (as an in-database copy)
 :)
declare function format:combine(
  $doc as document-node(),
  $params as map,
  $original-doc as document-node()
  ) as document-node() {
  let $unflats := format:unflatten-dependencies($doc, $params)
  let $cmb := combine:combine-document(?, $params)
  return
    mirror:apply-if-outdated(
      $format:combine-cache,
      mirror:doc($format:unflatten-cache, document-uri($doc)),
      $cmb,
      $original-doc
    )
};

(:~ perform the transform up to the HTML formatting step 
 : @param $doc The document to be transformed
 : @param $params Parameters to pass to the transforms
 : @param $original-doc The original document that is being transformed (may be the same as $doc) 
 : @param $transclude Use transclusion?
 : @return The combined document (as an in-database copy)
 :)
declare function format:html(
  $doc as document-node(),
  $params as map,
  $original-doc as document-node(),
  $transclude as xs:boolean
  ) as document-node() {
  let $html := tohtml:tohtml-document(?, $params)
  return
    mirror:apply-if-outdated(
      $format:html-cache,
      if ($transclude)
      then format:combine($doc, $params, $original-doc)
      else format:unflatten($doc, $params, $original-doc),
      $html,
      $original-doc
    )
};


declare function format:transliterate(
  $uri-or-node as item(),
  $user as xs:string?,
  $password as xs:string?
  ) as document-node() {
  local:wrap-document(
    app:transform-xslt($uri-or-node, 
      app:concat-path($format:rest-path-to-xslt, 'translit/translit-main.xsl2'),
      (
        if ($user)
        then (
          <param name="user" value="{$user}"/>,
          <param name="password" value="{$password}"/>
        )
        else (), 
        <param name="transliteration-tables" value="{
          string-join(
            collection("/data/transliteration")/tr:schema/document-uri(root(.)),
            " ")
        }"/>
      ), ()
    )
  )
};

