<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
<xsl:output omit-xml-declaration="no" method="xml" doctype-public="-//W3C//DTD XHTML 1.0 Strict//EN" doctype-system="http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd" indent="yes" encoding="UTF-8" />
<xsl:template match="/icestats">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
	<title><xsl:value-of select="host" /> — Stream status</title>
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
				<li><a class="is-active" href="status.xsl">Server Status</a></li>
				<li><a href="server_version.xsl">Version</a></li>
			</ul>
		</div>

		<header class="hero">
			<h1 class="brand">Stream status</h1>
			<p class="tagline">Active mounts and what’s playing now.</p>
		</header>

		<section class="mounts">
			<xsl:for-each select="source">
				<xsl:choose>
					<xsl:when test="listeners">
						<article class="mount">
							<div class="mount-head">
								<h2 class="mount-title">
									<span class="live-dot" aria-hidden="true"></span>
									<span><xsl:value-of select="@mount" /></span>
								</h2>
								<div>
									<xsl:choose>
										<xsl:when test="authenticator">
											<a class="auth-link" href="/auth.xsl">Login</a>
										</xsl:when>
										<xsl:otherwise>
											<ul class="mount-actions">
												<li><a href="{@mount}">Listen</a></li>
												<li><a href="{@mount}.m3u">M3U</a></li>
												<li><a href="{@mount}.xspf">XSPF</a></li>
											</ul>
										</xsl:otherwise>
									</xsl:choose>
								</div>
							</div>
							<div class="mount-body">
								<xsl:if test="server_type and ((server_type = 'application/ogg') or (server_type = 'audio/ogg'))">
									<div class="audioplayer">
										<audio controls="controls" preload="none">
											<source src="{@mount}" type="{server_type}" />
										</audio>
									</div>
								</xsl:if>
								<table class="meta">
									<tbody>
										<xsl:if test="server_name">
											<tr>
												<th scope="row">Stream name</th>
												<td><xsl:value-of select="server_name" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="server_description">
											<tr>
												<th scope="row">Description</th>
												<td><xsl:value-of select="server_description" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="server_type">
											<tr>
												<th scope="row">Content type</th>
												<td><xsl:value-of select="server_type" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="stream_start">
											<tr>
												<th scope="row">Started</th>
												<td><xsl:value-of select="stream_start" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="bitrate">
											<tr>
												<th scope="row">Bitrate</th>
												<td><xsl:value-of select="bitrate" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="quality">
											<tr>
												<th scope="row">Quality</th>
												<td><xsl:value-of select="quality" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="video_quality">
											<tr>
												<th scope="row">Video quality</th>
												<td><xsl:value-of select="video_quality" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="frame_size">
											<tr>
												<th scope="row">Framesize</th>
												<td><xsl:value-of select="frame_size" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="frame_rate">
											<tr>
												<th scope="row">Framerate</th>
												<td><xsl:value-of select="frame_rate" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="genre">
											<tr>
												<th scope="row">Genre</th>
												<td><xsl:value-of select="genre" /></td>
											</tr>
										</xsl:if>
										<xsl:if test="server_url">
											<tr>
												<th scope="row">Stream URL</th>
												<td><a href="{server_url}"><xsl:value-of select="server_url" /></a></td>
											</tr>
										</xsl:if>
										<tr>
											<th scope="row">Now playing</th>
											<td class="now-playing">
												<xsl:if test="artist"><xsl:value-of select="artist" /> — </xsl:if>
												<xsl:value-of select="title" />
											</td>
										</tr>
									</tbody>
								</table>
							</div>
						</article>
					</xsl:when>
					<xsl:otherwise>
						<div class="offline"><xsl:value-of select="@mount" /> — not connected</div>
					</xsl:otherwise>
				</xsl:choose>
			</xsl:for-each>

			<xsl:if test="not(source[listeners])">
				<div class="empty">No active mounts right now. When an encoder connects, the stream will show up here.</div>
			</xsl:if>
		</section>

	</div>
</body>
</html>
</xsl:template>
</xsl:stylesheet>
