/*
 * Copyright 2012-2024 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.springframework.boot.testsupport;

import java.io.File;

public class TestResource {

	private static final boolean REWRITE_PATHS = Boolean
		.parseBoolean(System.getProperty("org.springframework.boot.testsupport.TestResource.rewritePaths", "false"));

	private final String path;

	public TestResource(String path) {
		this.path = rewritePath(path);
	}

	public File toFile() {
		return new File(this.path);
	}

	public String getPath() {
		return this.path;
	}

	@Override
	public String toString() {
		return this.path;
	}

	private static String rewritePath(String path) {
		if (!REWRITE_PATHS) {
			return path;
		}

		if (path.startsWith("/")) {
			throw new IllegalStateException("'" + path + "' must not start with a '/'");
		}

		if (path.startsWith("src/test/resources")) {
			return rewritePath(path, "src/test/resources", "build/resources/test");
		}
		else if (path.startsWith("src/intTest/resources")) {
			return rewritePath(path, "src/intTest/resources", "build/resources/intTest");
		}

		throw new IllegalStateException("Unexpected test resource location '" + path + "'");
	}

	private static String rewritePath(String path, String from, String to) {
		if (path.equals(from)) {
			return to;
		}
		return to + "/" + path.substring(from.length() + 1);
	}

}
