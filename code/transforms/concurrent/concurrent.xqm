xquery version "3.0";
(:~ Concurrent processing
 : @author Efraim Feinstein
 :
 : Copyright 2009-2012 Efraim Feinstein
 : Open Siddur Project
 : Licensed under the GNU Lesser General Public License, version 3 and above 
 :)
module namespace conc="http://jewishliturgy.org/transform/concurrent";

import module namespace uri="http://jewishliturgy.org/transform/uri"
  at "/code/modules/follow-uri.xqm";
import module namespace intl="http://jewishliturgy.org/transform/intermediate-links"
  at "intermediate-links.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace j="http://jewishliturgy.org/ns/jlptei/1.0";
declare namespace jf="http://jewishliturgy.org/ns/jlptei/flat/1.0";

(:
  <xsl:import href="../copy-context.xsl2"/>
  <xsl:import href="intermediate-links.xsl2"/>
  <xsl:import href="parallel.xsl2"/>
  <xsl:import href="resolve-internal.xsl2"/>
  <xsl:import href="set-priorities.xsl2"/>
  <xsl:include href="flatten.xsl2" />
  <xsl:include href="standoff-views.xsl2" />
  <xsl:include href="../follow-uri.xsl2" />
  
  <xsl:strip-space elements="*"/>
  
:)

declare function conc:conc(
  $nodes as node()*
  ) {
  for $n in $nodes
  return
    typeswitch($n)
    case text() return text { normalize-space($n) }
    case element(j:links) return conc:j-links($n)
    case element(tei:TEI) return conc:tei-TEI($n)
    case element() return
      if ($n/@xml:id)
      then conc:default-element-xmlid($n)
      else conc:default-element($n)
    default return conc:conc($n/node())
};

(:~ Catch tei:TEI, add a j:links section and run 
 : intermediate-links mode, if necessary
 :)
declare function conc:tei-TEI(
  $e as element(tei:TEI)
  ) {
  element tei:TEI {
    $e/@*,
    conc:mark-cache-dependencies($e),
    if (empty($e/j:links))
    then
      let $int-links :=
        intl:intermediate-links($e//j:concurrent)
      where exists($int-links)
      return
        element j:links { $int-links }
    else (),
    conc:conc($e/node())
  }
};

(:~ Catch j:links, switch into intermediate-links mode :)
declare function conc:j-links(
  $e as element(j:links)
  ) {
  intl:intermediate-links($e)
};

(:~ mark cache dependencies with a jf:cache-depend element :)
declare function conc:mark-cache-dependencies(
  $e as element()
  ) as element(jf:cache-depend)* {
  let $this-doc := document-uri(root($e))
  for $v in
    distinct-values(
      for 
        $ptr in root($e)//tei:ptr[not(@type="url")],
        $target in tokenize($ptr/@target, "\s+")[not(starts-with(., "http://"))]
      return 
        resolve-uri(
          uri:uri-base-path(
            uri:absolutize-uri($target, $ptr)
          ),
          base-uri($ptr)
        )[not(. = $this-doc)]
    )
  return
    <jf:cache-depend path="{$v}"/>
};

(:~ Find @xml:id and convert it to @jf:id in default mode.
 : Low priority; higher priority templates will have to 
 : convert on their own
 :)
declare function conc:default-element-xmlid(
  $e as element()
  ) {
  element { QName(namespace-uri($e), name($e)) }{
    $e/(@* except @xml:id),
    attribute jf:id { $e/@xml:id },
    conc:conc($e/node())
  }
};

(:

  <xd:doc type="element(jx:joined-concurrent)">
    <xd:short>Match concurrent hierarchies.  Return a parsed forms of the 
    hierarchies joined together</xd:short>
    <xd:detail>Leaves attributes @jx:document-uri and @xml:base so pointers
    and the document source can be resolved.</xd:detail>
    <xd:param name="additional-views">additional views to process as if 
    they were part of the current hierarchy</xd:param>
  </xd:doc>
  <xsl:template match="j:concurrent[j:selection]" as="element(jx:joined-concurrent)">
    <xsl:param name="additional-views" tunnel="yes" as="element(j:view)*"
      select="()"/>
    <xsl:sequence select="func:debug($additional-views, 'concurrent:additional-views', $debug-detail)"/>   
    <xsl:variable name="context" select="." as="element(j:concurrent)"/>
    <xsl:sequence select="func:debug(($context/j:selection/@jx:uid, generate-id($context/j:selection)), 'j:concurrent selection id (uid, generate-id)', $debug-detail)"/>
        
    <xsl:variable name="processed-concurrent" 
      as="element(jx:merged-concurrent-parallel)">
      <xsl:call-template name="process-concurrent">
        <xsl:with-param name="resolved-views" as="element(j:view)*">
          <xsl:apply-templates mode="resolve-internal" 
            select="j:view|$additional-views">
          </xsl:apply-templates>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:variable>
    
    <xsl:variable name="unflattened" as="element(jx:unflattened)">
      <jx:unflattened>
        <xsl:call-template name="copy-attributes-and-context"/>
        <xsl:apply-templates 
          select="$processed-concurrent/element()[1]"
          mode="unflatten"/>
      </jx:unflattened>
    </xsl:variable>
    
    <xsl:sequence select="func:debug($unflattened, '$unflattened', $debug-detail)"/>
    
    <xsl:variable name="expanded-internal" as="element()">
      <xsl:apply-templates select="$unflattened" mode="expand-internal">
        <xsl:with-param name="document-context" as="element()"
          select="$context" tunnel="yes"/>
      </xsl:apply-templates>
    </xsl:variable>
    
    <xsl:sequence select="func:debug($expanded-internal, '$expanded-internal', $debug-detail)"/>
    
    <jx:joined-concurrent>
      <!-- copy the context here, if changed -->
      <xsl:if test="@xml:id">
        <xsl:attribute name="jx:id" select="@xml:id"/>
      </xsl:if>
      <xsl:call-template name="copy-attributes-and-context-if-changed">
        <xsl:with-param name="attributes" as="attribute()*" select="@* except @xml:id"/>
      </xsl:call-template>
      <!--xsl:attribute name="jx:document-uri" select="func:document-id(root(.))"/-->
      <xsl:apply-templates select="$expanded-internal" mode="cleanup-unflatten"/>
    </jx:joined-concurrent>
	</xsl:template>

  <xd:doc>
    <xd:short>Perform most of the concurrent processing operations</xd:short>
    <xd:detail>This is a helper template</xd:detail>
    <xd:param name="resolved-views">Result of mode=resolve-internal</xd:param>
  </xd:doc>
  <xsl:template name="process-concurrent" 
    as="element(jx:merged-concurrent-parallel)">
    <xsl:param name="resolved-views" as="element(j:view)*" required="yes"/>
    
    <xsl:variable name="context" as="element(j:concurrent)" select="."/>
    <xsl:sequence select="func:debug($resolved-views, 'resolved-views', $debug-detail)"/>
    
    <xsl:variable name="set-priorities" as="element(j:view)*">
      <xsl:apply-templates select="$resolved-views" mode="set-priorities"/>
    </xsl:variable>
    <xsl:sequence select="func:debug($set-priorities, 'set-priorities', $debug-detail)"/>
    
    <xsl:variable name="flattened-views" as="element(jx:flat-view)*">
      <xsl:apply-templates mode="flatten" select="$set-priorities"/>
    </xsl:variable>
    <xsl:sequence select="func:debug($flattened-views,'$flattened-views',$debug-detail)"/>
    
    <xsl:variable name="merged-to-selection" as="element(jx:merged-view)*">
      <xsl:for-each select="$flattened-views">
        <xsl:apply-templates select="$context/j:selection" 
          mode="merge-view-to-selection">
          <xsl:with-param name="view" tunnel="yes" 
            select="." as="element(jx:flat-view)"/>
        </xsl:apply-templates>
      </xsl:for-each>
    </xsl:variable>
    <xsl:sequence select="func:debug($merged-to-selection,'$merged-to-selection', $debug-detail)"/>
    
    <xsl:variable name="merged-concurrent" as="element(jx:merged-selection)">
      <xsl:apply-templates select="j:selection" mode="merge-concurrent">
        <xsl:with-param name="flattened-views" as="element(jx:merged-view)*"
          tunnel="yes" select="$merged-to-selection"/>
      </xsl:apply-templates>
    </xsl:variable>
    <xsl:sequence select="func:debug($merged-concurrent,'$merged-concurrent', $debug-detail)"/>
    
    <xsl:variable name="merged-concurrent-sorted" 
      as="element(jx:merged-selection)">
      <jx:merged-selection>
        <xsl:call-template name="sort-flat-hierarchy-by-priority">
          <xsl:with-param name="sequence" as="element()+"
            select="$merged-concurrent/element()"/>
          <xsl:with-param name="selection-id" as="xs:string"
            select="(j:selection/@jx:uid, generate-id(j:selection))[1]"/>
        </xsl:call-template>
      </jx:merged-selection>
    </xsl:variable>
    <xsl:sequence select="func:debug($merged-concurrent-sorted, '$merged-concurrent-sorted', $debug-detail)"/>

    <!-- BUG: ready-flattened-for-parallel-proccessing treats original
    and parallel differently-->
    <xsl:variable name="merged-concurrent-parallel" 
      as="element(jx:merged-concurrent-parallel)">
      <jx:merged-concurrent-parallel>
        <xsl:apply-templates select="$merged-concurrent-sorted/element()[1]" 
          mode="ready-flattened-for-parallel-processing">
          <xsl:with-param name="selection-id" as="xs:string"
            select="(j:selection/@jx:uid, generate-id(j:selection))[1]" tunnel="yes"/>
        </xsl:apply-templates>
      </jx:merged-concurrent-parallel>
    </xsl:variable>
    <xsl:sequence select="func:debug($merged-concurrent-parallel, '$merged-concurrent-parallel', $debug-detail)"/>
    
    <xsl:sequence select="$merged-concurrent-parallel"/>
  </xsl:template>

  <xsl:template match="j:view" mode="filter-parallel-source">
    <xsl:copy>
      <xsl:call-template name="copy-attributes-and-context"/>
      <xsl:apply-templates mode="#current"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="j:parallel|j:original" mode="filter-parallel-source">
    <xsl:param name="source" as="xs:string" tunnel="yes" required="yes"/>
    <xsl:if test="@n = $source">
      <xsl:copy>
        <xsl:copy-of select="@* except @jx:uid"/>
        <xsl:attribute name="jx:uid" select="(@jx:uid, generate-id())[1]"/>
        <xsl:apply-templates mode="#current"/>
      </xsl:copy>
    </xsl:if>
  </xsl:template>
  
  <xsl:template match="*" mode="filter-parallel-source">
    <xsl:copy>
      <xsl:copy-of select="@* except @jx:uid"/>
      <xsl:attribute name="jx:uid" select="(@jx:uid, generate-id())[1]"/>
      <xsl:apply-templates mode="#current"/>
    </xsl:copy>
  </xsl:template>
  <!-- TODO: rename tei:ptr @type=selection to j:selectionRef/(@target,@n->@name) -->
  <xd:doc>
    <xd:short>j:concurrent for parallel texts</xd:short>
  </xd:doc>
  <xsl:template match="j:concurrent[not(j:selection)]" 
    as="element(jx:joined-concurrent)">
    <xsl:variable name="context" select="." as="element(j:concurrent)"/>
    <!-- this is a document node so it can be searched by UID -->
    <xsl:variable name="processed-concurrents" as="document-node()">
      <xsl:document>
        <jx:processed-concurrents>
          <xsl:for-each select="tei:ptr[@type='selection']">
            <xsl:variable name="current-selection" as="element(j:selection)">
              <xsl:apply-templates select="." mode="follow-uri"/>
            </xsl:variable>
            <xsl:variable name="current-parallel-view" as="element(j:view)">
              <xsl:apply-templates select="$context/j:view" mode="filter-parallel-source">
                <xsl:with-param name="source" tunnel="yes" as="xs:string" select="@n"/>
              </xsl:apply-templates>
            </xsl:variable>
            <xsl:variable name="concurrent" as="element(j:concurrent)"
              select="$current-selection/parent::j:concurrent"/>
            <jx:processed-concurrent n="{@n}">
              <xsl:for-each select="$concurrent">
                <xsl:call-template name="process-concurrent">
                  <xsl:with-param name="resolved-views" as="element(j:view)*">
                    <xsl:apply-templates mode="resolve-internal" 
                      select="j:view|$current-parallel-view">
                      <xsl:with-param name="full-context" as="xs:boolean" tunnel="yes" 
                        select="true()"/>
                    </xsl:apply-templates>
                  </xsl:with-param>
                </xsl:call-template>
              </xsl:for-each>
            </jx:processed-concurrent>
          </xsl:for-each>
        </jx:processed-concurrents>
      </xsl:document>
    </xsl:variable>
    <xsl:sequence select="func:debug($processed-concurrents, '$processed-concurrents', $debug-detail)"/>
    
    <xsl:variable name="all-merged" as="element(jx:merged-concurrents)">
      <jx:merged-concurrents>
        <xsl:apply-templates 
          select="j:view[@type='parallelGrp']/*" mode="merge-parallels">
          <xsl:with-param name="parallel" tunnel="yes" 
            select="$processed-concurrents"
            as="document-node(element(jx:processed-concurrents))"/>
        </xsl:apply-templates>
      </jx:merged-concurrents>
    </xsl:variable>
    <xsl:sequence select="func:debug($all-merged, '$all-merged', $debug-detail)"/>
    
    <xsl:variable name="unflattened" as="element(jx:unflattened)">
      <jx:unflattened>
        <xsl:call-template name="copy-attributes-and-context"/>
        <xsl:apply-templates 
          select="$all-merged/element()[1]"
          mode="unflatten"/>
      </jx:unflattened>
    </xsl:variable>
    
    <xsl:sequence select="func:debug($unflattened, '$unflattened', $debug-detail)"/>
    
    <xsl:variable name="expanded-internal" as="element()">
      <xsl:apply-templates select="$unflattened" mode="expand-internal"/>
    </xsl:variable>
    
    <xsl:sequence select="func:debug($expanded-internal, '$expanded-internal', $debug-detail)"/>
    
    <jx:joined-concurrent>
      <!-- copy the context here, if changed -->
      <xsl:if test="@xml:id">
        <xsl:attribute name="jx:id" select="@xml:id"/>
      </xsl:if>
      <xsl:call-template name="copy-attributes-and-context-if-changed">
        <xsl:with-param name="attributes" as="attribute()*" select="@* except @xml:id"/>
      </xsl:call-template>
      <xsl:apply-templates select="$expanded-internal" mode="cleanup-unflatten">
      </xsl:apply-templates>
    </jx:joined-concurrent>
  </xsl:template>
  
  <xd:doc>
    <xd:short>Select the right parallel or original for each element</xd:short>
    <xd:param name="parallel">The processed parallel hierarchy that is 
    concurrent to this one.</xd:param>
  </xd:doc>
  <xsl:template match="j:parallel|j:original" mode="merge-parallels">
    <xsl:param name="parallel" tunnel="yes" 
      as="document-node(element(jx:processed-concurrents))" required="yes"/>
    <xsl:sequence 
      select="key('uids', (@jx:uid, generate-id())[1], $parallel)"/>
  </xsl:template>
  
  <xd:doc>
    <xd:doc>Every element that is not j:parallel|j:original is
    identity transformed.</xd:doc>
  </xd:doc>
  <xsl:template match="*" mode="merge-parallels">
    <xsl:call-template name="identity-in-mode"/>
  </xsl:template>
  
  <xd:doc>
    <xd:short>Form a merged-selection element</xd:short>
  </xd:doc>
  <xsl:template match="j:selection" mode="merge-concurrent">
    <xsl:variable name="unsorted-selection" 
      as="element(jx:merged-selection)">
      <jx:merged-selection>
        <xsl:apply-templates mode="#current"/>
      </jx:merged-selection>
    </xsl:variable>
    
    <xsl:variable name="selection-id" as="xs:string"
      select="(@jx:uid, generate-id(.))[1]"/>
    <jx:merged-selection>
      <xsl:call-template name="copy-attributes-and-context"/>
      <xsl:for-each-group select="$unsorted-selection/element()"
        group-starting-with="tei:ptr[@jx:selection=$selection-id]">
        <xsl:variable name="this-ptr" 
          select="current-group()/self::tei:ptr[@jx:selection=$selection-id]" 
          as="element(tei:ptr)?"/>
        <xsl:sequence select="$this-ptr"/>
         
        <xsl:apply-templates select="current-group() except $this-ptr"
          mode="remove-duplicates"
          >
          <!-- xsl:sort select="if (@jx:end) then -@jx:priority else @jx:priority" 
            stable="yes" data-type="number"/-->
        </xsl:apply-templates>
      </xsl:for-each-group>
    </jx:merged-selection>
  </xsl:template>
  
  <xd:doc>
    <xd:short>Copy only one copy of a starting element, removing
    attributes added in the concurrent.xsl2 process</xd:short>
    <xd:detail>After this mode:
      <ul>
        <li>Each *[@jx:uid] only has one @jx:start and</li>
        <li>@jx:parents and @jx:ancestors reflect the parents and ancestors from both views</li>
      </ul>
    </xd:detail>
  </xd:doc>
  <xsl:template match="element()[@jx:start]" 
    mode="remove-duplicates">
    <xsl:variable name="duplicates" as="element()*" 
        select="following-sibling::*[@jx:start and @jx:uid=current()/@jx:uid]"/>
    <xsl:sequence select="if ($duplicates) then
      func:debug(('duplicates of ' , ., 'are',$duplicates), 'remove-duplicates',$debug-detail)
      else ()"/>    
    <xsl:if test="empty($duplicates)">
      <!-- preceding duplicates in document order -->
      <xsl:variable name="preceding-duplicates" as="element()*"
        select="reverse(preceding-sibling::*[@jx:uid=current()/@jx:uid])"/>
      <!-- <xsl:call-template name="copy-and-remove-added-attributes"/> -->
      <!-- xsl:variable name="in-views" as="xs:string"
        select="string-join((@jx:in, $duplicates/@jx:in), ' ')"/-->
      <xsl:variable name="parents" as="xs:string*"
        select="($preceding-duplicates/@jx:parents, @jx:parents)"/>
      <xsl:variable name="ancestors" as="xs:string*"
        select="for $anc in ($preceding-duplicates/@jx:ancestors, @jx:ancestors) 
          return tokenize($anc, '\s')"/>
      
      <xsl:copy>
        <xsl:copy-of select="@* except 
          ((:@jx:in,:) @jx:ancestors, @jx:parents (:, @jx:selection:) )"/>
        <!-- xsl:attribute name="jx:in" select="$in-views"/-->
        <xsl:if test="exists($parents)">
          <xsl:attribute name="jx:parents"
            select="string-join(distinct-values($parents), ' ')"/>
        </xsl:if>
        <xsl:if test="exists($ancestors)">
          <xsl:attribute name="jx:ancestors" 
            select="string-join(distinct-values($ancestors), ' ')"/>
        </xsl:if>
      </xsl:copy>
    </xsl:if>
  </xsl:template>
  
  <xd:doc>
    <xd:short>Copy only one copy of an ending element, removing
    attributes added in the concurrent.xsl2 process</xd:short>
  </xd:doc>
  <xsl:template match="element()[@jx:end]" 
    mode="remove-duplicates">
    <xsl:variable name="duplicates" as="element()*" 
        select="preceding-sibling::*[@jx:end and @jx:uid=current()/@jx:uid]"/>
    <xsl:if test="empty($duplicates)">
      <!-- <xsl:call-template name="copy-and-remove-added-attributes"/>-->
      <!-- <xsl:call-template name="copy-and-remove-added-attributes"/> -->
      <!-- xsl:variable name="in-views" as="xs:string"
        select="string-join((@jx:in, $duplicates/@jx:in), ' ')"/-->
      <xsl:copy>
        <xsl:copy-of select="@* except ((:@jx:in,:) @jx:selection)"/>
        <!-- xsl:attribute name="jx:in" select="$in-views"/-->
      </xsl:copy>
    </xsl:if>  
  
  </xsl:template>
  
  <xd:doc>
    <xd:short>Copy only one copy of an element containing no start or end 
    marker, removing attributes added in the concurrent.xsl2 process</xd:short>
  </xd:doc>
  <xsl:template match="element()[not(@jx:start|@jx:end)]" 
    mode="remove-duplicates">
    <xsl:variable name="duplicates" as="element()*" 
      select="following-sibling::*[@jx:uid=current()/@jx:uid]"/>

    <xsl:if test="empty($duplicates)">
      <!-- preceding duplicates in document order -->
      <xsl:variable name="preceding-duplicates" as="element()*"
        select="reverse(preceding-sibling::*[@jx:uid=current()/@jx:uid])"/>
      <xsl:variable name="parents" as="xs:string*"
        select="($preceding-duplicates/@jx:parents, @jx:parents)"/>
      <xsl:variable name="ancestors" as="xs:string*"
        select="(for $anc in ($preceding-duplicates/@jx:ancestors, @jx:ancestors) return tokenize($anc, '\s'))"/>

      <!-- <xsl:call-template name="copy-and-remove-added-attributes"/> -->
      <!-- xsl:variable name="in-views" as="xs:string"
        select="string-join((@jx:in, $duplicates/@jx:in), ' ')"/-->
      <xsl:copy>
        <xsl:copy-of select="@* except (@jx:parents, @jx:ancestors) (: except (@jx:in, @jx:selection) :)"/>
        <xsl:if test="exists($parents)">
          <xsl:attribute name="jx:parents" 
            select="string-join(distinct-values($parents), ' ')"/>
        </xsl:if>
        <xsl:if test="exists($ancestors)">
          <xsl:attribute name="jx:ancestors" 
            select="string-join(distinct-values($ancestors), ' ')"/>
        </xsl:if>
        <xsl:apply-templates mode="identity"/>
      </xsl:copy>
    </xsl:if>
  </xsl:template>
  
  <xd:doc>
    <xd:short>Copy a single element, removing unnecessary attributes added 
    during the concurrent.xsl2 processing (@jx:selection)</xd:short>
  </xd:doc>
  <xsl:template name="copy-and-remove-added-attributes">
    <xsl:copy>
      <xsl:copy-of select="@* except (@jx:selection)"/>
      <xsl:apply-templates mode="identity"/>
    </xsl:copy>
  </xsl:template>
  
  <xd:doc>
    <xd:short>The "meat" of the merge-concurrent operation.</xd:short>
    <xd:detail>Combine and dump all of the flat hierarchies, 
      avoid duplicates</xd:detail>
  </xd:doc>
  <xsl:template match="tei:ptr" mode="merge-concurrent">
    <xsl:param name="flattened-views" as="element(jx:merged-view)*"
      tunnel="yes" required="yes"/>
    
    <xsl:variable name="xmlid" select="(@jx:id, @xml:id)[1]"/>
    <xsl:variable name="my-selection" as="element(j:selection)" select="parent::j:selection"/>
    <xsl:variable name="selection-id" as="xs:string" 
      select="($my-selection/@jx:uid, generate-id($my-selection))[1]"/>
    
    <!-- if a selection has no views (is all external pointers), 
    the pointer should be copied, with xml:id->jx:id, and jx:selection/jx:uid added 
    (should this even be legal?)
    -->
    <xsl:if test="empty($flattened-views)">
      <xsl:copy>
        <xsl:call-template name="copy-attributes-and-context">
          <xsl:with-param name="attributes" as="attribute()*" select="@* except @xml:id"/>
        </xsl:call-template>
        <xsl:if test="@xml:id">
          <xsl:attribute name="jx:id" select="(@jx:id, @xml:id)"/>
        </xsl:if>
        <xsl:attribute name="jx:uid" select="(@jx:uid, generate-id())[1]"/>
        <xsl:attribute name="jx:selection" select="$selection-id"/> 
      </xsl:copy>
    </xsl:if>
    
    <xsl:if test="not(preceding-sibling::tei:ptr)">
      <xsl:for-each select="$flattened-views">
        <xsl:sequence 
          select="tei:ptr[@jx:selection=$selection-id]
            [$xmlid=(@jx:id,@xml:id)]/preceding-sibling::node()"/>
      </xsl:for-each>
    </xsl:if>
    
    <xsl:for-each select="$flattened-views">
      <xsl:variable name="equivalent-ptr" as="element(tei:ptr)?"
        select="tei:ptr[@jx:selection=$selection-id][$xmlid=(@jx:id,@xml:id)]"/>
      <xsl:sequence select="$equivalent-ptr/preceding-sibling::node()
        intersect
        $equivalent-ptr/preceding-sibling::tei:ptr
          [@jx:selection=$selection-id][1]/following-sibling::node()"/>
    </xsl:for-each>
    <xsl:for-each select="$flattened-views[1]/tei:ptr
      [@jx:selection=$selection-id][$xmlid=(@jx:id,@xml:id)]">
      <xsl:copy>
        <xsl:copy-of select="@* (:except @jx:in:)"/>
        <!-- xsl:attribute name="jx:in" 
          select="string-join($flattened-views/tei:ptr[@xml:id=$xmlid]/@jx:in, 
            ' ')"/-->
      </xsl:copy>
    </xsl:for-each>
    <!-- last pointer in the selection, grab all tags -->
    <xsl:if test="not(following-sibling::tei:ptr)">
      <xsl:for-each select="$flattened-views">
        <xsl:sequence select="tei:ptr[@jx:selection=$selection-id]
          [$xmlid=(@xml:id,@jx:id)]/following-sibling::node()"/>
      </xsl:for-each>
    </xsl:if>
  </xsl:template>
  
  <xd:doc type="element(jx:merged-view)">
    <xd:short>Merge view to the given selection.
    The view is already flattened. 
    Return a jx:merged-view element
    </xd:short>
    <xd:param name="view">A flattened view to be merged with
    the given selection.</xd:param>
  </xd:doc>
  <xsl:template match="j:selection" mode="merge-view-to-selection" as="element(jx:merged-view)">
    <xsl:param name="view" tunnel="yes" required="yes" 
      as="element(jx:flat-view)"/>
    <jx:merged-view>
      <xsl:call-template name="copy-attributes-and-context"/>
      <xsl:sequence select="func:debug(generate-id(.), 'merge-view-to-selection selection id', $debug-detail)"/>
      <xsl:apply-templates mode="#current"/>
    </jx:merged-view>
  </xsl:template>
 
  <xd:doc>
    <xd:short>Clobber text nodes</xd:short>
  </xd:doc>
  <xsl:template match="text()" mode="merge-view-to-selection"/>
 
  <xd:doc>
    <xd:short>Catch tei:ptr in merge-view-to-selection mode.
    The expected context is a selection, all views to be incorporated
    are included in parameter $view.  The output is a merged entity,
    with the following properties:
    <ul>
      <li>All pointers contained in the selection are present and in the 
      correct position with respect to the contents of the view.</li>
      <li>If a view skips any selection pointers, any open tags at the
      point of the skip are "closed" with an element with @jx:suspend.  
      They are reopened with @jx:continue after the skip.</li>
      <li>At a suspend, all elements up to the last end element are 
      considered to be before the suspension.  
      After it are after the suspension.</li>
      <li>If any views duplicate each other, the duplicates are present</li>
      <li>The pointers coming from all the views are unsorted.</li>
    </ul>
    </xd:short>
    <xd:param name="view">(Enhanced) flattened views.</xd:param>
  </xd:doc>
  <xsl:template match="tei:ptr" mode="merge-view-to-selection">
    <xsl:param name="view" tunnel="yes" required="yes" 
      as="element(jx:flat-view)"/>
    
    <!-- jx:uid can be put on j:selection in order to make a reproducible id, eg, for testing -->
    <xsl:variable name="my-selection" as="element(j:selection)" select="parent::j:selection"/> 
    <!-- for DEBUGGING: selection-id should be traced if you think nodes are coming from the wrong
    file/uri -->
    <xsl:variable name="selection-id" as="xs:string"
      select="($my-selection/@jx:uid, generate-id($my-selection))[1]"/>
    <!-- xsl:variable name="" as="xs:string" select=""/-->
    <xsl:sequence select="func:debug(('@xml:id = ', string((@xml:id,@jx:id)[1]), ', $view = ', $view),'tei:ptr[merge-view-to-selection]', $debug-detail)"/>
    <xsl:variable name="equivalent-ptr" as="element(tei:ptr)?" 
      select="$view/tei:ptr[@jx:selection=$selection-id]
        [(@jx:id,@xml:id)=current()/(@xml:id, @jx:id)]"/>
    <xsl:choose>
      <xsl:when test="$equivalent-ptr">
        <!--  this pointer is present in the given view -->
        <xsl:variable name="preceding-selection-ptr" as="element(tei:ptr)?"
          select="$equivalent-ptr/preceding-sibling::tei:ptr
            [@jx:selection=$selection-id]
            [(@jx:id,@xml:id)=../tei:ptr/(@xml:id,@jx:id)][1]"/>
        <xsl:variable name="following-selection-ptr" as="element(tei:ptr)?"
          select="$equivalent-ptr/following-sibling::tei:ptr
            [@jx:selection=$selection-id]
            [(@xml:id,@jx:id)=(../tei:ptr/@xml:id,../tei:ptr/@jx:id)][1]"/>
        
        <xsl:variable name="preceding-to-current" as="node()*"
          select="if ($preceding-selection-ptr) then
                    $equivalent-ptr/preceding-sibling::node() intersect
                      $preceding-selection-ptr/following-sibling::node()
                  else $equivalent-ptr/preceding-sibling::node()"/>
        <xsl:variable name="current-to-following" as="node()*"
          select="if ($following-selection-ptr) then
                    $equivalent-ptr/following-sibling::node() intersect
                      $following-selection-ptr/preceding-sibling::node()
                  else $equivalent-ptr/following-sibling::node()"/>
         
        <xsl:sequence select="func:debug((
          'equivalent-ptr: ', $equivalent-ptr,
          'preceding-selection-ptr: ', $preceding-selection-ptr,
          'following-selection-ptr: ', $following-selection-ptr,
          'preceding-to-current: ', $preceding-to-current,
          'current-to-following: ', $current-to-following,
          'preceding-sibling::tei:ptr[1]/@xml:id: ', string(preceding-sibling::tei:ptr[1]/@xml:id),
          'following-sibling::tei:ptr[1]/@xml:id: ', string(following-sibling::tei:ptr[1]/@xml:id)), 
        'tei:ptr in merge-view-to-selection mode', $debug-detail)"/>
        
        <!-- copy preceding starting tags and preceding start tags  -->
        <xsl:choose>
          <xsl:when test="empty($preceding-selection-ptr)">
            <xsl:sequence select="func:debug('empty $preceding-selection-ptr', 'tei:ptr',$debug-detail)"/>
            <xsl:sequence select="$preceding-to-current"/>
          </xsl:when>
          <xsl:when test="not(($preceding-selection-ptr/@xml:id, $preceding-selection-ptr/@jx:id) = 
            (preceding-sibling::tei:ptr[1]/@xml:id, preceding-sibling::tei:ptr[1]/@jx:id))">
            
          <!-- the previous pointer had a skip, take everything after 
          the last @jx:end -->
          <!-- insert continues here -->
          <xsl:for-each select="
              $equivalent-ptr/preceding-sibling::element()[@jx:start]
              except $preceding-to-current">
              <xsl:sort select="position()" data-type="number"/>
              <!-- 
              <xsl:sequence select="func:debug(('skip before',
          '. = ', .,
          '$equivalent-ptr/preceding-sibling::element()[@jx:end=current()/@jx:start] = ', 
            $equivalent-ptr/preceding-sibling::element()[@jx:end=current()/@jx:start]
          ), 'tei:ptr',$debug-detail)"/>
           -->
              <xsl:if test="not($equivalent-ptr/preceding-sibling::element()
                [@jx:end=current()/@jx:start])">
                <xsl:copy>
                  <xsl:copy-of select="@* except @jx:start"/>
                  <xsl:attribute name="jx:continue" select="@jx:start"/>
                </xsl:copy>
              </xsl:if>
            </xsl:for-each>
            <xsl:sequence select="$preceding-to-current
              [. &gt;&gt; $preceding-to-current[@jx:end][last()]]"/>
          </xsl:when>
          <xsl:otherwise/>
        </xsl:choose>
          
        <xsl:sequence select="$equivalent-ptr"/>
        
        <xsl:choose>
          <xsl:when test="empty($following-selection-ptr) or
            ($following-selection-ptr/@xml:id, $following-selection-ptr/@jx:id) =
              (following-sibling::tei:ptr[1]/@xml:id, following-sibling::tei:ptr[1]/@jx:id)">
            <xsl:sequence select="$current-to-following"/>
            <!-- 
            <xsl:sequence select="func:debug((
            'no skip after',
            'empty($following-selection-ptr) = ', empty($following-selection-ptr),
            '$following-selection-ptr/@xml:id = ', string($following-selection-ptr/@xml:id),
            'following-sibling::tei:ptr[1]/@xml:id = ', string(following-sibling::tei:ptr[1]/@xml:id),
            'equality = ', $following-selection-ptr/@xml:id eq following-sibling::tei:ptr[1]/@xml:id),
            'tei:ptr',$debug-detail)"/>
             -->
          </xsl:when>
          <xsl:otherwise>
            <!-- there's a break -->
            <!-- 
            <xsl:sequence select="func:debug(('skip after',
            '$current-to-following = ', $current-to-following,
            '$current-to-following
                [. &gt;&gt; $current-to-following[@jx:end][last()]] = ',
            $current-to-following
                [. &gt;&gt; $current-to-following[@jx:end][last()]],
            '(1) except (2) = ', $current-to-following except
              $current-to-following
                [. &gt;&gt; $current-to-following[@jx:end][last()]]
            ), 'tei:ptr',$debug-detail)"/>
             -->
            <xsl:sequence select="$current-to-following except
              $current-to-following
                [. &gt;&gt; $current-to-following[@jx:end][last()]]"/>
            <!-- insert suspends.  All started, but not ended tags get 
            suspended, in reverse order from creation -->
            <xsl:for-each select="
              $equivalent-ptr/preceding-sibling::element()[@jx:start]">
              <xsl:sort select="position()" data-type="number" order="descending"/>
              <xsl:if test="not($equivalent-ptr/preceding-sibling::element()
                [@jx:end=current()/@jx:start]) and
                not($current-to-following[@jx:end=current()/@jx:start])">
                <xsl:copy>
                  <xsl:copy-of select="@* except @jx:start"/>
                  <xsl:attribute name="jx:suspend" select="@jx:start"/>
                </xsl:copy>
              </xsl:if>
            </xsl:for-each>
          </xsl:otherwise>
        </xsl:choose>
        <!-- copy following ending tags (w/o same starting tags) -->
      </xsl:when>
      <xsl:otherwise>
        <!--  pointer is not present in the view, copy it in-place
         -->
        <xsl:copy>
          <xsl:copy-of select="@* except @xml:id"/>
          <xsl:if test="not(@jx:id)">
            <xsl:attribute name="jx:id" select="@xml:id"/>
          </xsl:if>
          <xsl:attribute name="jx:selection" select="$selection-id"/>
        </xsl:copy>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>


  <xsl:key name="uids" match="*" use="@jx:uid"/>
  <xsl:key name="parents-or-ancestors" match="*" use="(tokenize(@jx:parents,'\s+'), tokenize(@jx:ancestors, '\s+'))"/>
  <xd:doc>
    <xd:short>Sort a segment of flat hierarchy that does not have unmovable elements by ancestry</xd:short>
    <xd:detail>Sorting rules:
      <ul>
        <li>element()[@jx:end|@jx:suspend] can't be placed before last entry that has itself as parent or ancestor</li>
        <li>element()[@jx:start|@jx:continue] can't be placed after first entry that has self as parent or ancestor</li>
        <li>element()[not(@jx:start|@jx:end|...) must be placed after element()[@jx:start] of all parent|ancestor and
        	before element()[@jx:end] of all parent|ancestor</li>
      </ul>
    </xd:detail>
    <xd:param name="unsorted">remaining unsorted elements (as a document node so it can be indexed by keys)</xd:param>
    <xd:param name="sorted">already sorted elements (as a document node so it can be indexed by keys)</xd:param>
  </xd:doc>
  <xsl:template name="sort-flat-hierarchy-by-ancestry" as="element()*">
    <xsl:param name="unsorted" as="element()*"/>
    <xsl:param name="sorted" as="document-node(element(sorted))?"/>

    <xsl:variable name="to-sort" select="$unsorted[1]" as="element()?"/>
    <xsl:variable name="next-unsorted" select="subsequence($unsorted,2)" as="element()*"/>
    
    <xsl:variable name="parent-ids" as="xs:string*" select="tokenize($to-sort/@jx:parents,'\s+')"/>
    <xsl:variable name="ancestor-ids" as="xs:string*" select="tokenize($to-sort/@jx:ancestors,'\s+')"/>

    <xsl:choose>
      <xsl:when test="empty($unsorted)">
        <!-- nothing left to sort is the end condition for recursion -->
        <xsl:sequence select="$sorted/sorted/*"/>
      </xsl:when>
      <xsl:when test="empty($sorted)">
        <!-- nothing has been sorted yet.  Put the first element in the sorted bin and continue -->
        <xsl:call-template name="sort-flat-hierarchy-by-ancestry">
          <xsl:with-param name="unsorted" as="element()*" select="$next-unsorted"/>
          <xsl:with-param name="sorted" as="document-node(element(sorted))">
            <xsl:document>
              <sorted>
                <xsl:sequence select="$to-sort"/>
              </sorted>
            </xsl:document>
          </xsl:with-param>
        </xsl:call-template>
      </xsl:when>
      <xsl:when test="$to-sort/(@jx:start|@jx:continue)">
        <!-- $to-sort is a start element.  We want to push start elements as far to the end as possible -->
        <!-- first possible place for start is the last already sorted element  -->
        <xsl:variable name="last-ancestor-element" as="element()*"
          select="
          for $aid in $ancestor-ids 
          return key('parents-or-ancestors', $aid, $sorted)[@jx:start|@jx:continue]"/>
        <xsl:variable name="last-ancestor" as="xs:integer?" 
          select="
            if (exists($last-ancestor-element))
            then
              max(
                for $element in $last-ancestor-element
                return (1 + count($element/preceding-sibling::*))
              )
            else ()"/>
        <!-- last possible place for start -->
        <xsl:variable name="first-descendant-element" as="element()?" 
          select="key('parents-or-ancestors', $to-sort/@jx:uid, $sorted)[1]"/>
        <xsl:variable name="first-descendant" as="xs:integer?" 
          select="if (exists($first-descendant-element) and $to-sort/@jx:uid) 
            then (1 + count($first-descendant-element/preceding-sibling::*))
            else ()"/>
        <xsl:variable name="n-sorted" as="xs:integer" select="count($sorted/sorted/*)"/>
        <xsl:variable name="my-position" as="xs:integer" 
          select="
            if (exists($last-ancestor) and exists($first-descendant))
            then
              (1 to $n-sorted)[
                . &gt; $last-ancestor and 
                . &lt;= $first-descendant][last()]
            else if (exists($first-descendant))
            then $first-descendant
            else if (exists($last-ancestor))
            then $last-ancestor + 1
            else $n-sorted + 1
        "
        />
        <!-- 
<xsl:message>
=====sort-flat-hierarchy-by-ancestry for <xsl:sequence select="func:get-xpath($to-sort)"/>
=====$n-sorted = <xsl:value-of select="$n-sorted"/>
=====$my-position = <xsl:value-of select="$my-position"/>
=====$first-descendant = <xsl:value-of select="$first-descendant"/> $last-ancestor = <xsl:value-of select="$last-ancestor"/>
=====$to-sort = <xsl:sequence select="$to-sort"/>
=====$sorted = <xsl:sequence select="$sorted"/>
=====ancestors that we found = <xsl:sequence select="for $aid in $ancestor-ids
              return key('parents-or-ancestors', $aid, $sorted)[@jx:start|@jx:continue]"/>
=====END
</xsl:message>    
 -->    
        <xsl:call-template name="sort-flat-hierarchy-by-ancestry">
          <xsl:with-param name="unsorted" as="element()*" select="$next-unsorted"/>
          <xsl:with-param name="sorted" as="document-node(element(sorted))">
            <xsl:document>
              <sorted>
                <xsl:sequence select="insert-before($sorted/sorted/*, $my-position, $to-sort)"/>
              </sorted>
            </xsl:document>
          </xsl:with-param>
        </xsl:call-template>
      </xsl:when>
      <xsl:when test="$to-sort/(@jx:end|@jx:suspend)">
        <!-- $to-sort is an ending statement.  it is to be pushed as close to 1 as possible -->
        <!-- first ancestor's end.  Can't be placed before this -->
        <xsl:variable name="first-ancestor" as="xs:integer?" 
          select="if (exists($sorted))
            then min(
              for $aid in $ancestor-ids
              return key('parents-or-ancestors', $aid, $sorted)[@jx:end|@jx:suspend]/position()
            )
            else ()"/>
        <!-- last possible place for end -->
        <xsl:variable name="last-descendant" as="xs:integer?" 
          select="if (exists($sorted) and $to-sort/@jx:uid) 
            then key('parents-or-ancestors', $to-sort/@jx:uid, $sorted)[last()]/position()
            else ()"/>
        <xsl:variable name="n-sorted" as="xs:integer" select="count($sorted/sorted/*)"/>
        <xsl:variable name="my-position" as="xs:integer" 
          select="
            if (exists($last-descendant) and exists($first-ancestor))
            then
              (1 to $n-sorted)[
                . &gt; $last-descendant and 
                . &lt;= $first-ancestor][1]
            else if (exists($first-ancestor))
            then $first-ancestor
            else if (exists($last-descendant))
            then $last-descendant + 1
            else 1
        "
        />
        
        <xsl:call-template name="sort-flat-hierarchy-by-ancestry">
          <xsl:with-param name="unsorted" as="element()*" select="$next-unsorted"/>
          <xsl:with-param name="sorted" as="document-node(element(sorted))">
            <xsl:document>
              <sorted>
                <xsl:sequence select="insert-before($sorted/sorted/*, $my-position, $to-sort)"/>
              </sorted>
            </xsl:document>
          </xsl:with-param>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise><!-- no start, end, continue, or suspend-->
        <!-- $to-sort is an element that contains no pointers. it goes in the first possible place -->
        <xsl:variable name="ancestors" as="element()*" 
          select="
            if (exists($sorted))
            then
              for $aid in $ancestor-ids
              return key('parents-or-ancestors', $aid, $sorted)
            else ()
            "/>
        <xsl:variable name="last-ancestor-start" as="xs:integer?" 
          select="max($ancestors[@jx:start|@jx:continue]/position())"/>
        <xsl:variable name="first-ancestor-end" as="xs:integer?" 
          select="min($ancestors[@jx:end|@jx:suspend]/position())"/>
        <xsl:variable name="n-sorted" as="xs:integer" select="count($sorted/sorted/*)"/>
        <xsl:variable name="my-position" as="xs:integer" 
          select="
            if (exists($last-ancestor-start) and exists($first-ancestor-end))
            then
              (1 to $n-sorted)[
                . &gt; $last-ancestor-start and 
                . &lt;= $first-ancestor-end][last()]
            else if (exists($last-ancestor-start))
            then $last-ancestor-start + 1
            else if (exists($first-ancestor-end))
            then $first-ancestor-end
            else $n-sorted + 1
        "
        />
        
        <xsl:call-template name="sort-flat-hierarchy-by-ancestry">
          <xsl:with-param name="unsorted" as="element()*" select="$next-unsorted"/>
          <xsl:with-param name="sorted" as="document-node(element(sorted))">
            <xsl:document>
              <sorted>
                <xsl:sequence select="insert-before($sorted/sorted/*, $my-position, $to-sort)"/>
              </sorted>
            </xsl:document>
          </xsl:with-param>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xd:doc>
    <xd:short>Sort a flat hierarchy by priority, assuming that:
    <ul>
      <li>tei:ptr[@jx:selection] never moves from its relative position</li>
      <li>blocks of starting and ending elements can be moved</li>
      <li>other elements do not move relative to those blocks</li>
    </ul>
    </xd:short>
    <xd:param name="sequence">The sequence to sort.</xd:param>
    <xd:param name="selection-id">Identifier of the selection
    currently being processed</xd:param>
  </xd:doc>
  <xsl:template name="sort-flat-hierarchy-by-priority">
    <xsl:param name="sequence" as="element()*" required="yes"/>
    <xsl:param name="selection-id" as="xs:string" required="yes"/>
    <!-- TODO: group by selection-id or not!? -->
    <xsl:for-each-group select="$sequence"
      group-starting-with="tei:ptr[@jx:selection]">
      <!-- selection pointers never move with respect to anything else -->
      <xsl:variable name="this-ptr" as="element(tei:ptr)?" 
        select="current-group()/self::tei:ptr[@jx:selection]"/>
      <xsl:sequence select="$this-ptr"/>
      <xsl:for-each-group select="current-group() except $this-ptr" 
        group-adjacent="not(empty(@jx:priority))">
        <xsl:sequence select="func:debug(current-group(),('sort-flat-hierarchy-by-priority - group: ', string(position())),$debug-detail)"/>
        
        <xsl:sequence select="func:debug(('group = ', current-group()), 'sort-flat-hierarchy-by-priority', $debug-detail)"/>

        <xsl:call-template name="sort-flat-hierarchy-by-ancestry">
          <xsl:with-param name="unsorted" as="element()*">
            <xsl:perform-sort select="current-group()">
              <xsl:sort 
                select="@jx:priority" 
                data-type="number" stable="yes" 
                order="descending"/>
            </xsl:perform-sort>
          </xsl:with-param>
        </xsl:call-template>
      </xsl:for-each-group>
    </xsl:for-each-group>

  </xsl:template>
  
  
  <xd:doc>
    <xd:short>Simple helper function to convolve an existing xml:id to a
    part-unique generated ID for multipart elements</xd:short>
    <xd:param name="elem">The element for which to generate the ID</xd:param>
  </xd:doc>
  <xsl:function name="func:make-unique-xmlid" as="xs:string?">
    <xsl:param name="elem" as="element()?"/>
    <xsl:sequence select="
      if (empty($elem)) 
      then ()
      else if ($elem/(@xml:id, @jx:id)) 
      then string-join(($elem/(@jx:id, @xml:id)[1],'-',generate-id($elem)),'') 
      else generate-id($elem)"/>
  </xsl:function>
  
  <xd:doc>
    <xd:short>Clean up after unflatten by replacing @jx:part with 
    @next and @prev and assigning a new @xml:id; keep the old @xml:id
    in @jx:id</xd:short>
    <xd:detail>BUG? Will break if the element already had @next/@prev
    (I don't think this should ever happen)
    </xd:detail>
  </xd:doc>
  <xsl:template match="element()[@jx:part]" mode="cleanup-unflatten">
    <xsl:variable name="part-id" as="xs:string" select="@jx:part" />
    <xsl:variable name="previous-part" as="element()?"
      select="preceding::element()[@jx:part=$part-id][1][node()]"/>
    <xsl:variable name="next-part" as="element()?"
      select="following::element()[@jx:part=$part-id][1][node()]"/>
    <xsl:variable name="my-id" as="xs:string"
      select="func:make-unique-xmlid(.)"/>
    <xsl:variable name="previous-id" as="xs:string?"
      select="func:make-unique-xmlid($previous-part)"/>
    <xsl:variable name="next-id" as="xs:string?"
      select="func:make-unique-xmlid($next-part)"/>
    <xsl:sequence select="func:debug(('@jx:part:', $part-id,
      ' previous-part=', $previous-part,
      ' next-part=', $next-part,
      ' preceding=', preceding::element(),
      ' following=', following::element()),'cleanup-unflatten',
      $debug-detail + 1)"/>
    <xsl:copy>
      <xsl:call-template name="copy-attributes-and-context-if-changed">
        <xsl:with-param name="attributes" as="attribute()*"
          select="@* except (@jx:part,@xml:id,@jx:priority,@jx:id,@jx:uid,@jx:selection-origin)"/>
      </xsl:call-template>
      <xsl:if test="($next-part or $previous-part) and not(@xml:id = @jx:id)">
        <xsl:attribute name="xml:id" select="$my-id"/>
      </xsl:if>
      <xsl:attribute name="jx:id" select="(@jx:id, @xml:id, $my-id)[1]"/>
      <xsl:if test="$previous-part">
        <xsl:attribute name="prev" select="concat('#',$previous-id)"/>
      </xsl:if>
      <xsl:if test="$next-part">
        <xsl:attribute name="next" select="concat('#',$next-id)"/>
        <xsl:sequence select="func:debug(('adding next to ', $next-id), '@jx:part',$debug-info)"/>
      </xsl:if>
      <xsl:apply-templates mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xd:doc>
    <xd:short>Clean up after unflatten by removing added attributes</xd:short>
  </xd:doc>
  <xsl:template match="*" mode="cleanup-unflatten">
    <xsl:copy>
      <xsl:call-template name="copy-attributes-and-context-if-changed">
        <xsl:with-param name="attributes" as="attribute()*"
          select="@* except (@jx:priority, @jx:selection, @jx:uid, @jx:selection-origin, @xml:id)"/>
      </xsl:call-template>
      <xsl:if test="not(@xml:id = @jx:id)">
        <xsl:copy-of select="@xml:id"/>
      </xsl:if>
      <xsl:apply-templates mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xd:doc>
    <xd:short>Do not copy the jx:unflattened element</xd:short>
  </xd:doc>
  <xsl:template match="jx:unflattened" mode="cleanup-unflatten">
    <xsl:apply-templates mode="#current"/>
  </xsl:template>

  <xsl:template match="*" mode="expand-internal">
    <xsl:copy>
      <xsl:copy-of select="@* except @xml:id"/>
      <xsl:if test="@xml:id">
        <xsl:attribute name="jx:id" select="@xml:id"/>
      </xsl:if>
      <xsl:apply-templates mode="#current"/>
    </xsl:copy>
  </xsl:template>

  <xd:doc>
    <xd:short>Expand internal pointers in the selection with their content</xd:short>
    <xd:detail>External pointers in parallel groups are treated like internal pointers</xd:detail>
  </xd:doc>  
  <xsl:template match="tei:ptr[@jx:selection]" mode="expand-internal">
    <xsl:param name="document-context" as="element()" select="." tunnel="yes"/>
 
    <xsl:copy>
      <xsl:copy-of select="@*"/>
      <xsl:if test="exists(ancestor::j:parallelGrp) or 
        func:uri-base-path(
          func:absolutize-uri(@target, .))=func:original-document-uri(.)">
        <xsl:apply-templates mode="#current"
          select="func:follow-uri(@target, $document-context, func:follow-steps(., -1))"/>
      </xsl:if>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
:)