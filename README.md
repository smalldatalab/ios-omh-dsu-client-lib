OMHClient
======

This is the repository for the Open mHealth DSU iOS client library.

CLIENT SETUP
------------------------

In order to sign in to the DSU, your app will need two keys:

1. A DSU client ID for your app
2. The DSU client secret for your DSU client ID

Your app should use these keys to setup the client in your app delegate's `applicationDidFinishLaunching` by calling 
```
[OMHClient setupClientWithClientID:(1)
                      clientSecret:(2)];
```

CONTRIBUTE
----------

If you would like to contribute code to the Open mHealth iOS client you can do so through GitHub by forking the repository and sending a pull request.

You may [file an issue](https://github.com/smalldatalab/ios-omh-dsu-client-lib/issues) if you find bugs or would like to add a new feature.

LICENSE
-------

    Copyright (C) 2015 Open mHealth

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.