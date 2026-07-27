<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
<xsl:output omit-xml-declaration="no" method="xml" doctype-public="-//W3C//DTD XHTML 1.0 Strict//EN" doctype-system="http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd" indent="yes" encoding="UTF-8" />
<xsl:template match="/icestats">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<title><xsl:value-of select="host" /> — Server info</title>
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
	<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700&amp;display=swap" rel="stylesheet" />
	<link rel="stylesheet" type="text/css" href="style.css" />
	<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes" />
</head>
<body>
	<div class="shell">
		<div class="topbar">
			<a class="wordmark" href="status.xsl"><xsl:value-of select="host" /></a>
			<ul class="nav">
				<li><a href="admin/">Administration</a></li>
				<li><a href="status.xsl">Server Status</a></li>
				<li><a class="is-active" href="server_version.xsl">Version</a></li>
			</ul>
		</div>

		<header class="hero">
			<h1 class="brand">Server information</h1>
			<p class="tagline">Host details for this stream server.</p>
		</header>

		<article class="mount">
			<div class="mount-body">
				<table class="meta">
					<tbody>
						<xsl:for-each select="/icestats">
							<tr>
								<th scope="row">Location</th>
								<td><xsl:value-of select="location" /></td>
							</tr>
							<tr>
								<th scope="row">Admin</th>
								<td><xsl:value-of select="admin" /></td>
							</tr>
							<tr>
								<th scope="row">Host</th>
								<td><xsl:value-of select="host" /></td>
							</tr>
						</xsl:for-each>
					</tbody>
				</table>
			</div>
		</article>
	</div>
</body>
</html>
</xsl:template>
</xsl:stylesheet>
