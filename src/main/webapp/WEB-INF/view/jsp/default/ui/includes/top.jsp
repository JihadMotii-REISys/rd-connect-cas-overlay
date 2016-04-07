<%--

    Licensed to Apereo under one or more contributor license
    agreements. See the NOTICE file distributed with this work
    for additional information regarding copyright ownership.
    Apereo licenses this file to you under the Apache License,
    Version 2.0 (the "License"); you may not use this file
    except in compliance with the License.  You may obtain a
    copy of the License at the following location:

      http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing,
    software distributed under the License is distributed on an
    "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
    KIND, either express or implied.  See the License for the
    specific language governing permissions and limitations
    under the License.

--%>
<!DOCTYPE html>

<%@ page pageEncoding="UTF-8" %>
<%@ page contentType="text/html; charset=UTF-8" %>
<%@ taglib prefix="c" uri="http://java.sun.com/jsp/jstl/core" %>
<%@ taglib prefix="spring" uri="http://www.springframework.org/tags" %>
<%@ taglib prefix="form" uri="http://www.springframework.org/tags/form" %>
<%@ taglib prefix="fn" uri="http://java.sun.com/jsp/jstl/functions" %>

<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1">
  
  <title>RD-Connect Central Authentication Service</title>
  
  <spring:theme code="standard.custom.css.file" var="customCssFile" />
  <link rel="stylesheet" href="<c:url value="${customCssFile}" />" />
  <link rel="icon" href="<c:url value="/favicon.ico" />" type="image/x-icon" />
  <link rel="stylesheet" id="catalyst_enqueued_google_fonts-css" href="http://fonts.googleapis.com/css?family=Open+Sans%3Alight%2Clightitalic%2Cregular%2Cregularitalic%2C600%2C600italic%2Cbold%2Cbolditalic%2C800%2C800italic%7COswald%7CPT+Serif%3Aregular%2Citalic%2Cbold%2Cbolditalic%7C&amp;ver=3.7.11" type="text/css" media="all" />
  <!--[if lt IE 9]>
    <script src="//cdnjs.cloudflare.com/ajax/libs/html5shiv/3.6.1/html5shiv.js" type="text/javascript"></script>
  <![endif]-->
  <style>
	.toptitle {
		background-color: white;
		border-style: solid;
		border-color: #5F9758;
		border-width: 5px;
		box-sizing: border-box;
	}
	
	.rdtext {
		color: #21759B;
		font-size: 1.4em;
	}
  </style>
</head>
<body id="cas">
  <div id="container">
      <header>
        <h1 class="toptitle"><a href="http://rd-connect.eu/" title="<spring:message code="logo.title" />"><img src="images/rdconnect-logo.jpg" alt="RD-Connect"></a><span class="rdtext"> Central&nbsp;Authentication&nbsp;Service</span></h1>
      </header>
      <div id="content">
