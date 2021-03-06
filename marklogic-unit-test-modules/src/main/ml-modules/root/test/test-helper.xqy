(:
Copyright 2012-2015 MarkLogic Corporation

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
:)
xquery version "1.0-ml";

module namespace helper="http://marklogic.com/roxy/test-helper";

import module namespace cvt = "http://marklogic.com/cpf/convert" at "/MarkLogic/conversion/convert.xqy";

declare namespace t="http://marklogic.com/roxy/test";
declare namespace test="http://marklogic.com/roxy/test-helper";
declare namespace ss="http://marklogic.com/xdmp/status/server";
declare namespace xdmp-http="xdmp:http";

declare option xdmp:mapping "false";

declare variable $helper:PREVIOUS_LINE_FILE as xs:string :=
  try {
    fn:error(xs:QName("boom"), "")
  }
  catch($ex) {
    fn:concat($ex/error:stack/error:frame[3]/error:uri, " : Line ", $ex/error:stack/error:frame[3]/error:line)
  };

declare variable $helper:__LINE__ as xs:int :=
  try {
    fn:error(xs:QName("boom"), "")
  }
  catch($ex) {
    $ex/error:stack/error:frame[2]/error:line
  };

declare variable $helper:__CALLER_FILE__  := helper:get-caller() ;

declare function helper:get-caller()
as xs:string
{
  try { fn:error((), "ROXY-BOOM") }
  catch ($ex) {
    if ($ex/error:code ne 'ROXY-BOOM') then xdmp:rethrow()
    else (
      let $uri-list := $ex/error:stack/error:frame/error:uri/fn:string()
      let $this := $uri-list[1]
      return (($uri-list[. ne $this])[1], 'no file')[1])
  }
};

declare function helper:get-test-file($filename as xs:string)
as document-node()
{
  helper:get-test-file($filename, "text", "force-unquote")
};

declare function helper:get-test-file($filename as xs:string, $format as xs:string?)
as document-node()
{
  helper:get-test-file($filename, $format, ())
};

declare function helper:get-test-file($filename as xs:string, $format as xs:string?, $unquote as xs:string?)
as document-node()
{
  helper:get-modules-file(
    fn:replace(
      fn:concat(
        cvt:basepath($helper:__CALLER_FILE__), "/test-data/", $filename),
      "//", "/"), $format, $unquote)
};

declare function helper:load-test-file($filename as xs:string, $database-id as xs:unsignedLong, $uri as xs:string)
{
  if ($database-id eq 0) then
    let $uri := fn:replace($uri, "//", "/")
    let $_ :=
      try {
        xdmp:filesystem-directory(cvt:basepath($uri))
      }
      catch($ex) {
        xdmp:filesystem-directory-create(cvt:basepath($uri),
          <options xmlns="xdmp:filesystem-directory-create">
            <create-parents>true</create-parents>
          </options>)
      }
    return
      xdmp:save($uri, helper:get-test-file($filename))
  else
    xdmp:eval('
      xquery version "1.0-ml";

      declare variable $uri as xs:string external;
      declare variable $file as node() external;
      xdmp:document-insert($uri, $file)
    ',
      (xs:QName("uri"), $uri,
      xs:QName("file"), helper:get-test-file($filename)),
      <options xmlns="xdmp:eval">
        <database>{$database-id}</database>
      </options>)
};

declare function helper:build-uri(
  $base as xs:string,
  $suffix as xs:string) as xs:string
{
  fn:string-join(
    (fn:replace($base, "(.*)/$", "$1"),
    fn:replace($suffix, "^/(.*)", "$1")),
    "/")
};

declare function helper:get-modules-file($file as xs:string) {
  helper:get-modules-file($file, "text", "force-unquote")
};

declare function helper:get-modules-file($file as xs:string, $format as xs:string?) {
  helper:get-modules-file($file, $format, ())
};

declare function helper:get-modules-file($file as xs:string, $format as xs:string?, $unquote as xs:string?) {
  let $doc :=
    if (xdmp:modules-database() eq 0) then
      xdmp:document-get(
        helper:build-uri(xdmp:modules-root(), $file),
        if (fn:exists($format)) then
          <options xmlns="xdmp:document-get">
            <format>{$format}</format>
          </options>
        else
          ())
    else
      xdmp:eval(
        'declare variable $file as xs:string external; fn:doc($file)',
        (xs:QName('file'), $file),
        <options xmlns="xdmp:eval">
          <database>{xdmp:modules-database()}</database>
        </options>)
  return
    if (fn:empty($unquote) or $doc/*) then
      $doc
    else
      if ($unquote eq "force-unquote") then
        try {
          xdmp:unquote($doc)
        }
        catch($ex) {
          $doc
        }
      else
        xdmp:unquote($doc)
};

(:~
 : constructs a success xml element
 :)
declare function helper:success() {
  <t:result type="success"/>
};

(:~
 : constructs a failure xml element
 :)
declare function helper:fail($expected as item(), $actual as item()) {
  helper:fail(<oh-nos>Expected {$expected} but got {$actual} at {$helper:PREVIOUS_LINE_FILE}</oh-nos>)
};

(:~
 : constructs a failure xml element
 :)
declare function helper:fail($message as item()*) {
  element t:result {
    attribute type { "fail" },
    typeswitch($message)
      case element(error:error) return $message
      default return
        fn:error(xs:QName("USER-FAIL"), $message)
  }
};

declare function helper:assert-all-exist($count as xs:unsignedInt, $item as item()*) {
  if ($count eq fn:count($item)) then
    helper:success()
  else
    fn:error(xs:QName("ASSERT-ALL-EXIST-FAILED"), "Assert All Exist failed", $item)
};

declare function helper:assert-exists($item as item()*) {
  if (fn:exists($item)) then
    helper:success()
  else
    fn:error(xs:QName("ASSERT-EXISTS-FAILED"), "Assert Exists failed", $item)
};

declare function helper:assert-not-exists($item as item()*) {
  if (fn:not(fn:exists($item))) then
    helper:success()
  else
    fn:error(xs:QName("ASSERT-NOT-EXISTS-FAILED"), "Assert Not Exists failed", $item)
};

declare function helper:assert-at-least-one-equal($expected as item()*, $actual as item()*) {
  if ($expected = $actual) then
    helper:success()
  else
    fn:error(xs:QName("ASSERT-AT-LEAST-ONE-EQUAL-FAILED"), "Assert At Least one Equal failed", ())
};

declare private function helper:are-these-equal($expected as item()*, $actual as item()*) {
  if (fn:count($expected) eq fn:count($actual)) then
    if ($expected instance of json:array and $actual instance of json:array) then
      helper:assert-equal-json-recursive($expected, $actual)
    else
      fn:count((
        for $item at $i in $expected
        return
          fn:deep-equal($item, $actual[$i]))[. = fn:true()]) eq fn:count($expected)
  else
    fn:false()
};

(: Return true if and only if the two sequences have the same values, regardless
 : of order. fn:deep-equal() returns false if items are not in the same order. :)
declare function helper:assert-same-values($expected as item()*, $actual as item()*)
{
  let $expected-ordered :=
    for $e in $expected
    order by $e
    return $e
  let $actual-ordered :=
    for $a in $actual
    order by $a
    return $a
  return helper:assert-equal($expected-ordered, $actual-ordered)
};

declare function helper:assert-equal($expected as item()*, $actual as item()*) {
  if (helper:are-these-equal($expected, $actual)) then
    helper:success()
  else
    fn:error(xs:QName("ASSERT-EQUAL-FAILED"), "Assert Equal failed", ($expected, $actual))
};

declare function helper:assert-equal($expected as item()*, $actual as item()*, $error-object as item()*) {
  if (helper:are-these-equal($expected, $actual)) then
    helper:success()
  else
    fn:error(xs:QName("ASSERT-EQUAL-FAILED"), "Assert Equal failed", ($expected, $actual, " : ", $error-object))
};

declare function helper:assert-not-equal($expected as item()*, $actual as item()*) {
  if (fn:not(helper:are-these-equal($expected, $actual))) then
    helper:success()
  else
    fn:error(
      xs:QName("ASSERT-NOT-EQUAL-FAILED"),
      fn:concat("test name", ": Assert Not Equal failed"),
      ($expected, $actual))
};

declare function helper:assert-equal-xml($expected, $actual) {
  typeswitch ($actual)
    case document-node() return
      typeswitch ($expected)
        case document-node() return
          helper:assert-equal-xml($expected/node(), $actual/node())
        default return
          helper:assert-equal-xml($expected, $actual/node())
    case element() return
      if (fn:empty($expected)) then
        helper:assert-true(fn:false(), ("element not found in $expected : ", xdmp:path($actual)))
      else typeswitch ($expected)
        case element() return (
          helper:assert-equal(fn:name($expected), fn:name($actual), ("mismatched node name ($expected=", xdmp:path($expected), ", $actual=", xdmp:path($actual), ")")),
          helper:assert-equal(fn:count($expected/@*), fn:count($actual/@*), ("mismatched attribute count ($expected=", xdmp:path($expected), ", $actual=", xdmp:path($actual), ")")),
          for $attribute in $actual/@* return
            helper:assert-equal-xml($expected/@*[fn:name(.) = fn:name($attribute)], $attribute),
          for $text at $i in $actual/text() return
            helper:assert-equal(fn:normalize-space($expected/text()[$i]), fn:normalize-space($text), ("mismatched element text ($expected=", xdmp:path($expected), ", $actual=", xdmp:path($actual), ")")),
          helper:assert-equal(fn:count($expected/*), fn:count($actual/*), ("mismatched element count ($expected=", xdmp:path($expected), ", $actual=", xdmp:path($actual), ")")),
          for $element at $i in $actual/* return
            helper:assert-equal-xml($expected/*[$i], $element)
        )
        default return
          helper:assert-true(fn:false(), ("type mismatch ($expected=", xdmp:path($expected), ", $actual=", xdmp:path($actual), ")"))
    case attribute() return
      if (fn:empty($expected)) then
        helper:assert-true(fn:false(), ("attribute not found in $expected : ", xdmp:path($actual)))
      else typeswitch ($expected)
        case attribute() return (
          helper:assert-equal(fn:name($expected), fn:name($actual), ("mismatched attribute name ($expected=", xdmp:path($expected), ", $actual=", xdmp:path($actual), ")")),
          helper:assert-equal($expected/fn:data(), $actual/fn:data(), ("mismatched attribute text ($expected=", xdmp:path($expected), ", $actual=", xdmp:path($actual), ")"))
        )
        default return
          helper:assert-true(fn:false(), ("type mismatch : $expected=", xdmp:path($expected), ", $actual=", xdmp:path($actual)))
    default return
      helper:assert-true(fn:false(), ("unsupported type in $actual : ", xdmp:path($actual)))
};

declare function helper:assert-equal-json($expected, $actual) {
  if ($expected instance of object-node()*) then
    if ($actual instance of object-node()*) then
      if (fn:count($expected) = fn:count($actual)) then
        if (helper:assert-equal-json-recursive($expected, $actual)) then
          helper:success()
        else
          fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed", ($expected, $actual))
      else
        fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed (different counts of objects)", ($expected, $actual))
    else
      (: $actual is not object-node()* :)
      fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed ($actual does not consist of objects)", ($expected, $actual))
  else if ($expected instance of map:map*) then
    if ($actual instance of map:map*) then
      if (fn:count($expected) = fn:count($actual)) then
        if (helper:assert-equal-json-recursive($expected, $actual)) then
          helper:success()
        else
          fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed", ($expected, $actual))
      else
        fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed (different counts of objects)", ($expected, $actual))
    else
      fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed ($actual does not consist of objects)", ($expected, $actual))
  else if ($expected instance of array-node()*) then
    if ($actual instance of array-node()*) then
      if (fn:count($expected) = fn:count($actual)) then
        if (helper:assert-equal-json-recursive($expected, $actual)) then
          helper:success()
        else
          fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed", ($expected, $actual))
      else
        fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed (different counts of arrays)", ($expected, $actual))
    else
      fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed ($actual does not consist of arrays)", ($expected, $actual))
  else if ($expected instance of document-node()) then
    if ($actual instance of document-node()) then
      if (fn:count($expected) = fn:count($actual)) then
        if (helper:assert-equal-json-recursive($expected/node(), $actual/node())) then
          helper:success()
        else
          fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed (documents not equal)", ($expected, $actual))
      else
        fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed (different counts of documents)", ($expected, $actual))
    else
      fn:error(xs:QName("ASSERT-EQUAL-JSON-FAILED"), "Assert Equal Json failed ($actual is not a document)", ($expected, $actual))
  else
    (: scalar values :)
    helper:assert-equal($expected, $actual)
};

declare function helper:assert-equal-json-recursive($object1, $object2) as xs:boolean
{
  typeswitch($object1)
    case map:map return
      let $k1 := map:keys($object1)
      let $k2 :=
        if ($object2 instance of map:map) then
          map:keys($object2)
        else
          fn:error(
            xs:QName("ASSERT-EQUAL-JSON-FAILED"),
            "Assert Equal Json failed: comparing map to non-map",
            ($object1, $object2)
          )
      let $counts-equal := fn:count($k1) eq fn:count($k2)
      let $maps-equal :=
        for $key in map:keys($object1)
        let $v1 := map:get($object1, $key)
        let $v2 := map:get($object2, $key)
        return
          helper:assert-equal-json-recursive($v1, $v2)
      return $counts-equal and fn:not($maps-equal = fn:false())
    case json:array return
      let $counts-equal := fn:count($object1) = fn:count($object2)
      let $items-equal :=
        let $o1 := json:array-values($object1)
        let $o2 :=
          if ($object2 instance of json:array) then
            json:array-values($object2)
          else
            fn:error(
              xs:QName("ASSERT-EQUAL-JSON-FAILED"),
              "Assert Equal JSON failed: comparing json:array to non-array",
              ($object1, $object2)
            )
        for $item at $i in $o1
        return
          helper:assert-equal-json-recursive($item, $o2[$i])
      return
        $counts-equal and fn:not($items-equal = fn:false())
    case object-node() return
      let $m1 := fn:data($object1)
      let $m2 :=
        if ($object2 instance of object-node()) then
          fn:data($object2)
        else
          fn:error(
            xs:QName("ASSERT-EQUAL-JSON-FAILED"),
            "Assert Equal JSON failed: comparing object-node to non-object-node",
            ($object1, $object2)
          )
      let $k1 := map:keys($m1)
      let $k2 := map:keys($m2)
      let $counts-equal := fn:count($k1) eq fn:count($k2)
      let $maps-equal :=
        for $key in map:keys($m1)
        let $v1 := map:get($m1, $key)
        let $v2 := map:get($m2, $key)
        return
          helper:assert-equal-json-recursive($v1, $v2)
      return $counts-equal and fn:not($maps-equal = fn:false())
    default return
      $object1 = $object2
};

declare function helper:assert-true($supposed-truths as xs:boolean*) {
  helper:assert-true($supposed-truths, $supposed-truths)
};

declare function helper:assert-true($supposed-truths as xs:boolean*, $msg as item()*) {
  if (fn:false() = $supposed-truths) then
    fn:error(xs:QName("ASSERT-TRUE-FAILED"), "Assert True failed", $msg)
  else
    helper:success()
};

declare function helper:assert-false($supposed-falsehoods as xs:boolean*) {
  if (fn:true() = $supposed-falsehoods) then
    fn:error(xs:QName("ASSERT-FALSE-FAILED"), "Assert False failed", $supposed-falsehoods)
  else
    helper:success()
};


declare function helper:assert-meets-minimum-threshold($expected as xs:decimal, $actual as xs:decimal+) {
  if (every $i in 1 to fn:count($actual) satisfies $actual[$i] ge $expected) then
    helper:success()
  else
    fn:error(
      xs:QName("ASSERT-MEETS-MINIMUM-THRESHOLD-FAILED"),
      fn:concat("test name", ": Assert Meets Minimum Threshold failed"),
      ($expected, $actual))
};

declare function helper:assert-meets-maximum-threshold($expected as xs:decimal, $actual as xs:decimal+) {
  if (every $i in 1 to fn:count($actual) satisfies $actual[$i] le $expected) then
    helper:success()
  else
    fn:error(
      xs:QName("ASSERT-MEETS-MAXIMUM-THRESHOLD-FAILED"),
      fn:concat("test name", ": Assert Meets Maximum Threshold failed"),
      ($expected, $actual))
};

declare function helper:assert-throws-error($function as xdmp:function)
{
  helper:assert-throws-error_($function, json:to-array(), ())
};

declare function helper:assert-throws-error($function as xdmp:function, $error-code as xs:string?)
{
  helper:assert-throws-error_($function, json:to-array(), $error-code)
};

declare function helper:assert-throws-error($function as xdmp:function, $param1 as item()*, $error-code as xs:string?)
{
  helper:assert-throws-error_($function, json:to-array( (json:to-array($param1), json:to-array('make me a sequence')), 1 ), $error-code)
};

declare function helper:assert-throws-error($function as xdmp:function, $param1 as item()*, $param2 as item()*, $error-code as xs:string?)
{
  helper:assert-throws-error_($function, json:to-array((json:to-array($param1), json:to-array($param2))), $error-code)
};

declare function helper:assert-throws-error($function as xdmp:function, $param1 as item()*, $param2 as item()*, $param3 as item()*, $error-code as xs:string?)
{
  helper:assert-throws-error_($function, json:to-array((json:to-array($param1), json:to-array($param2), json:to-array($param3))), $error-code)
};

declare function helper:assert-throws-error($function as xdmp:function, $param1 as item()*, $param2 as item()*, $param3 as item()*, $param4 as item()*, $error-code as xs:string?)
{
  helper:assert-throws-error_($function, json:to-array((json:to-array($param1), json:to-array($param2), json:to-array($param3), json:to-array($param4))), $error-code)
};

declare function helper:assert-throws-error($function as xdmp:function, $param1 as item()*, $param2 as item()*, $param3 as item()*, $param4 as item()*, $param5 as item()*, $error-code as xs:string?)
{
  helper:assert-throws-error_($function, json:to-array((json:to-array($param1), json:to-array($param2), json:to-array($param3), json:to-array($param4), json:to-array($param5))), $error-code)
};

declare function helper:assert-throws-error($function as xdmp:function, $param1 as item()*, $param2 as item()*, $param3 as item()*, $param4 as item()*, $param5 as item()*, $param6 as item()*, $error-code as xs:string?)
{
  helper:assert-throws-error_($function, json:to-array((json:to-array($param1), json:to-array($param2), json:to-array($param3), json:to-array($param4), json:to-array($param5), json:to-array($param6))), $error-code)
};

declare private function helper:assert-throws-error_($function as xdmp:function, $params as json:array, $error-code as xs:string?)
{
  let $size := json:array-size($params)
  return
    try {
      if ($size eq 0) then
        xdmp:apply($function)
      else if ($size eq 1) then
        xdmp:apply($function, json:array-values($params[1]))
      else if ($size eq 2) then
          xdmp:apply($function, json:array-values($params[1]), json:array-values($params[2]))
        else if ($size eq 3) then
            xdmp:apply($function, json:array-values($params[1]), json:array-values($params[2]), json:array-values($params[3]))
          else if ($size eq 4) then
              xdmp:apply($function, json:array-values($params[1]), json:array-values($params[2]), json:array-values($params[3]), json:array-values($params[4]))
            else if ($size eq 5) then
                xdmp:apply($function, json:array-values($params[1]), json:array-values($params[2]), json:array-values($params[3]), json:array-values($params[4]), json:array-values($params[5]))
              else if ($size eq 6) then
                  xdmp:apply($function, json:array-values($params[1]), json:array-values($params[2]), json:array-values($params[3]), json:array-values($params[4]), json:array-values($params[5]), json:array-values($params[6]))
                else (: arbitrary fall-back :)
                  xdmp:apply($function, json:array-values($params))
      ,
      fn:error(xs:QName("ASSERT-THROWS-ERROR-FAILED"), "It did not throw an error")
    }
    catch($ex) {
      if ($ex/error:name eq "ASSERT-THROWS-ERROR-FAILED") then
        xdmp:rethrow()
      else if ($error-code) then
        if ($ex/error:code eq $error-code or $ex/error:name eq $error-code) then
          helper:success()
        else
          (
            fn:error(xs:QName("ASSERT-THROWS-ERROR-FAILED"), fn:concat("Error code was: ", $ex/error:code, " not: ", $error-code))
          )
      else
        helper:success()
    }
};

declare variable $local-url as xs:string := xdmp:get-request-protocol() || "://localhost:" || xdmp:get-request-port();
declare variable $helper:DEFAULT_HTTP_OPTIONS := element xdmp-http:options {
  let $credential-id := xdmp:invoke-function(function() {
      xdmp:apply(xdmp:function(xs:QName('sec:credential-get-id'), "/MarkLogic/security.xqy"), "marklogic-unit-test-credentials")
    }, map:entry("database", xdmp:security-database()))
  return
    element xdmp-http:credential-id {$credential-id}
};

declare function helper:easy-url($url) as xs:string
{
  if (fn:starts-with($url, "http")) then $url
  else
    fn:concat($local-url, if (fn:starts-with($url, "/")) then "" else "/", $url)
};

declare function helper:http-get($url as xs:string, $options as item()? (:as (element(xdmp-http:options)|map:map)?:))
{
  let $uri := helper:easy-url($url)
  return
    xdmp:http-get($uri, $options)
};

declare function helper:assert-http-get-status($url as xs:string, $options as item()? (:as (element(xdmp-http:options)|map:map)?:), $status-code)
{
  let $response := helper:http-get($url, $options)
  return
    test:assert-equal($status-code, fn:data($response[1]/*:code))
};

declare function helper:http-post($url as xs:string, $options as item()? (:as (element(xdmp-http:options)|map:map)?:), $data as node()?)
{
  let $uri := helper:easy-url($url)
  return
    xdmp:http-post($uri, $options, $data)
};

declare function helper:assert-http-post-status($url as xs:string, $options as item()? (:as (element(xdmp-http:options)|map:map)?:), $data as node()?, $status-code)
{
  let $response := helper:http-post($url, $options, $data)
  return
    test:assert-equal($status-code, fn:data($response[1]/*:code))
};

declare function helper:http-put($url as xs:string, $options as item()? (:as (element(xdmp-http:options)|map:map)?:), $data as node()?)
{
  let $uri := helper:easy-url($url)
  return
    xdmp:http-put($uri, $options, $data)
};

declare function helper:assert-http-put-status($url as xs:string, $options as item()? (:as (element(xdmp-http:options)|map:map)?:), $data as node()?, $status-code)
{
  let $response := helper:http-put($url, $options, $data)
  return
    test:assert-equal($status-code, fn:data($response[1]/*:code))
};

(:~
 : Convenience function to remove all xml docs from the data db
 :)
declare function helper:delete-all-xml() {
  xdmp:eval('for $x in (cts:uri-match("*.xml"), cts:uri-match("*.xlsx"))
             where fn:not(fn:contains($x, "config/config.xml"))
             return
              try {xdmp:document-delete($x)}
              catch($ex) {()}')
};

declare function helper:wait-for-doc($pattern, $sleep) {
  if (xdmp:eval(fn:concat("cts:uri-match('", $pattern, "')"))) then ()
  else
    (
      xdmp:sleep($sleep),
      helper:wait-for-doc($pattern, $sleep)
    )
};

declare function helper:wait-for-truth($truth as xs:string, $sleep) {
  if (xdmp:eval($truth)) then ()
  else
    (
      xdmp:sleep($sleep),
      helper:wait-for-truth($truth, $sleep)
    )
};

declare function helper:wait-for-taskserver($sleep) {
(: do the sleep first. on some super awesome computers the check for active
     tasks can return 0 before they have a change to queue up :)
  helper:log(fn:concat("Waiting ", $sleep, " msec for taskserver..")),
  xdmp:sleep($sleep),

  let $group-servers := xdmp:group-servers(xdmp:group())
  let $task-server := xdmp:server("TaskServer")[. = $group-servers]
  let $status := xdmp:server-status(xdmp:host(), $task-server)
  let $queue-size as xs:unsignedInt := $status/ss:queue-size
  let $active-requests as xs:unsignedInt := fn:count($status/ss:request-statuses/ss:request-status)
  return
    if ($queue-size = 0 and $active-requests = 0) then
      helper:log("Done waiting for taskserver!")
    else
      helper:wait-for-taskserver($sleep)
};

(:~
 : Convenience function to invoke a sleep
 :)
declare function helper:sleep($msec as xs:unsignedInt) as empty-sequence() {
  xdmp:eval('declare variable $msec as xs:unsignedInt external;
             xdmp:sleep($msec)',
    (xs:QName("msec"), $msec))
};

declare function helper:log($items as item()*)
{
  let $_ := fn:trace($items, "UNIT-TEST")
  return ()
};

declare function helper:list-from-database(
  $database as xs:unsignedLong,
  $root as xs:string,
  $suite as xs:string?,
  $file-type as xs:string)
as xs:string*
{
  xdmp:eval(
    'xquery version "1.0-ml";
    declare variable $PATH as xs:string external;
    try { cts:uris((), (), cts:directory-query($PATH, "infinity")) }
    catch ($ex) {
      if ($ex/error:code ne "XDMP-URILXCNNOTFOUND") then xdmp:rethrow()
      else xdmp:directory($PATH, "infinity")/xdmp:node-uri(.) }',
    (xs:QName('PATH'),
    fn:concat($root, 'test/', $file-type, '/', ($suite, '')[1])),
    <options xmlns="xdmp:eval"><database>{$database}</database></options>)
};

(:
 : Use this function to clean up after tests that put stuff in the modules database.
 :)
declare function helper:remove-modules($uris as xs:string*)
{
  if (xdmp:modules-database() ne 0) then
    xdmp:eval('
      xquery version "1.0-ml";
      declare variable $uris external;

      $uris ! xdmp:document-delete(.)',
      map:new((map:entry("uris", $uris))),
      <options xmlns="xdmp:eval">
        <database>{xdmp:modules-database()}</database>
      </options>)
  else ()
};

(:
 : Use this function to clean up after tests that put stuff in the modules database.
 :)
declare function helper:remove-modules-directories($dirs as xs:string*)
{
  if (xdmp:modules-database() ne 0) then
    xdmp:eval('
      xquery version "1.0-ml";
      declare variable $dirs external;

      $dirs ! xdmp:directory-delete(.)',
      map:new((map:entry("dirs", $dirs))),
      <options xmlns="xdmp:eval">
        <database>{xdmp:modules-database()}</database>
      </options>)
  else ()
};

(: unquote text and get the actual doc content, but without tabs and newlines. convenience function. :)
declare function helper:unquote($doc-text as xs:string)
   as document-node()
 {
  let $doc := fn:head(xdmp:unquote($doc-text))
  return helper:strip-blanks($doc)
};

declare function helper:strip-blanks($n as node()) {
  typeswitch($n)
  case document-node() return document{$n/node() ! helper:strip-blanks(.)}
  case element() return element{node-name($n)} {$n/@*, $n/node() ! helper:strip-blanks(.)}
  case text() return if (fn:normalize-space($n) eq '') then () else $n
 default return $n
};
