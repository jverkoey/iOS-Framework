Building a static iOS framework is a pain. There are a variety of existing solutions
already and each one has its own disadvantages. Presented here is a solution that meets all of the
following constraints while having no deal-breaking disadvantages.

- Fast iterative compilation times (up to 3x faster than some solutions!).
- Easy distribution and packaging.
- No modifications to Xcode.
- No trickery with fake bundle targets and the likes.
- Simple set-up for third-parties.
- Support for building the framework as a dependent target (i.e. modifying source in the framework
  and building an app will automatically rebuild the framework and relink as expected).
- Works with the latest version of Xcode

Shameless plug: if you appreciate high-speed iOS development, check out
[Nimbus](http://nimbuskit.info/), the iOS framework whose growth is bounded by its
documentation.

<a rel="license" href="http://creativecommons.org/licenses/by/3.0/"><img alt="Creative Commons License" style="border-width:0" src="http://i.creativecommons.org/l/by/3.0/88x31.png" /></a><br />This work is licensed under a <a rel="license" href="http://creativecommons.org/licenses/by/3.0/">Creative Commons Attribution 3.0 Unported License</a>.

## Important notice regarding Swift code

The Swift language, as of Nov 2015, is still in flux. By including Swift code in your
distributed binary .framework, you are forcing the users of your framework to have the
same version of Swift as when you built your framework. **This is bad** because it will
eventually result in your clients encountering the following error:

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/swift-error.png)

While Swift the language is still changing, we **highly recommend** that you **do not**
build Swift code into your .frameworks. This applies to both *static* and *dynamic*
frameworks.

With that out of the way, let's learn how to make a static iOS framework...built only
with Objective-C.

Table of Contents
=================

- [Existing Solutions](#existing_solutions)
- [How to Create a Static Framework for iOS](#walkthrough)
  - [Overview](#overview)
  - [Create the Static Library Target](#static_library_target)
  - [Create the Framework Distribution Target](#framework_distribution_target)
- [Resources and Bundles](#resources)
- [Adding the Framework to a Third-Party Application](#third_parties)
- [Developing the Framework as a Dependent Project](#first_parties)
- [FAQ](#faq)
- [License](#license)

<a name="existing_solutions" />

Existing Solutions
==================

Presented below are a few of the most popular solutions for building static iOS frameworks and the
reasons why they should be avoided.

> Note: Though the tone below is largely critical, credit is owed to those who pioneered these
> solutions. Much of the proposed solution is based off the work that these amazingly generous
> people have donated to the ether. Thanks!

iOS-Universal-Framework
-----------------------

Source: [https://github.com/kstenerud/iOS-Universal-Framework](https://github.com/kstenerud/iOS-Universal-Framework)

### Major problems

- Slow iterative build times
- Has to modify Xcode for "Real" frameworks
- Can't properly add framework as a dependent target for "Fake" frameworks
- No adequate solution for resource loading

### Overview

This project provides two solutions: "fake" frameworks and "real" frameworks.

A **fake** framework is a bundle target with a .framework extension and some post-build scripts to
generate the fat library for the .framework.

A **real** framework modifies the Xcode installation and generates a true .framework target. Real
frameworks also use post-build scripts to generate the fat library.

### Problems with Fake Frameworks

The problem with a fake framework is that you can't link to the framework as a dependent target. You
can "trick" Xcode into linking to the framework by using the `-framework` flag in your `LD_FLAGS`,
but changes to the framework will not be reflected in iterative builds. This requires that you clean
build every time you modify the framework, or make a trivial modification to the application itself
in order for it to forcefully relink to the new .framework. This bug is discussed
[here](https://github.com/kstenerud/iOS-Universal-Framework/issues/32).

*Example warning when you attempt to link to the .framework target:*

    warning: skipping file
    '/Users/featherless/Library/Developer/Xcode/DerivedData/SimpleApp-cshmhxdgzacibsgaiiryutjzobcb/Build/Products/Debug-iphonesimulator/fakeframework.framework'
    (unexpected file type 'wrapper.cfbundle' in Frameworks & Libraries build phase)

### Problems with Real Frameworks

To use real frameworks you need to modify your Xcode installation. This is simply not scalable when
you want to work with a team of people. If you use a build farm this problem becomes even worse
because it may not be possible to modify the Xcode installations on the build servers.

### Problems with Both Fake and Real Frameworks

In both frameworks there is a post-build step that builds the "inverse" platform. For example, if
you're building the framework for i386, the post-build step will build the framework for armv6/armv7/armv7s
and then smush the libraries together into one fat binary within the framework. The problem with
this is that it **triples** the build time of the framework. Make one change to a .m file and
suddenly you're rebuilding it for three platforms. Change a PCH and your project will effectively
perform three clean builds. This is simply not ok from a productivity standpoint.

There is also the problem of distributing resources with the .framework. Both the fake and real
frameworks include an "embeddedframework" which is meant to be copied into the application. This
results in the .framework binary being distributed with the application! Alternatively we could ask
developers to only copy what's in the resources folder to their app, but this is complicated and
requires we namespace our resource file names to avoid naming conflicts.

db-in's solution ("Fake" frameworks)
----------------

Source: http://db-in.com/blog/2011/07/universal-framework-iphone-ios-2-0/

### Major problems

- Slow iterative build times
- Can't properly add framework as a dependent target
- No adequate solution for resource loading (recommends a remarkably *bad* solution)

### Overview

db-in's solution is roughly identical to kstenerud's solution of using a bundle target to generate a
fake framework. This has the same disadvantages as outlined above so I won't repeat myself.

There is, however, a specific deal-breaker with the recommendations in this blog post: resources.
Db-in recommends copying the .framework into your application as a resource bundle; this is <b>NOT
OK</b>. This will end up copying not just the resources from your framework, but also the fat binary
of the framework! Doing this will inflate the size of your application by several megabytes more
than it should be because you're shipping off a fat binary with your application.

And so without further ado...

<a name="walkthrough" />

How to Create a Static Framework for iOS
========================================

There are a few constraints that we want to satisfy when building a .framework:

- Fast iterative builds when developing the framework. We may have a simple application that has the
  .framework as a dependency and we want to quickly iterate on development of the .framework.
- Infrequent distribution builds of the .framework.
- Resource distribution should be intuitive and not bloat the application.
- Setup for third-party developers using the .framework should be *easy*.

I believe that the solution I will outline below satisfies each of these constraints. I will outline
how to build a .framework project from scratch so that you can apply these steps to an existing
project if you so desire. I will also include project templates for easily creating a
.framework.

<a name="overview" />

Overview
--------

> View a sample project that shows the result of following these steps in the `sample/Serenity`
> directory.

Within the project we are going to have three targets: a static library, a bundle, and an aggregate.

The static library target will build the source into a static library (.a) and specify which headers
will be "public", meaning they will be accessible from the .framework when we distribute it.

The bundle target will contain all of our resources and will be loadable from the framework.

The aggregate target will build the static library for i386/armv6/armv7/armv7s, generate the fat framework
binary, and also build the bundle. You will run this target when you plan to distribute the
.framework.

When you are working on the framework you will likely have an internal application that links to the
framework. This application will link to the static library target as you normally would and copy
the .bundle in the copy resources phase. This has the benefit of only building the framework code
for the platform you're actively working on, significantly improving your build times. We'll do a
little bit of work in the framework project to ensure that you can use your framework in your app
the same way a third party developer would (i.e. importing <MyFramework/MyFramework.h> should work
as expected). <a href="#first_parties">Jump to the dependent project walkthrough</a>.

<a name="static_library_target" />

Create the Static Library Target
--------------------------------

### Step 1: Create a New "Cocoa Touch Static Library" Project

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/newstaticlib.png)

The product name will be the name of your framework. For example, `Serenity` will generate
`Serenity.framework` once we've set up the project.

### Step 2: Create the Primary Framework Header

Developers expect to be able to import your framework by importing the `<Serenity/Serenity.h>`
header. Ensure that your project has such a header (if you created a new static library then there
should already be a Serenity.h and Serenity.m file; you can delete the .m).

Within this header you are going to import all of the public headers for your framework. For
example, let's assume that we have some `Widget` with a .h and .m. Our Serenity.h file would look
like this:

```
#import <Foundation/Foundation.h>

#import <Serenity/Widget.h>
```

Once you've created your framework header file, you need to make it a "public" header. Public
headers are headers that will be copied to the .framework and can be imported by those using your
framework. This differs from "project" headers which will *not* be distributed with the framework.
This distinction is what allows you to have a concept of public and private APIs.

To change a file's [target membership visibility in XCode 4.4+]
(http://stackoverflow.com/questions/13571080/cant-change-target-membership-visibility-in-xcode-4-5),
you'll need to select the Static Library target you created (Serenity), open the Build Phases tab: 

**Xcode 4.X:**
Click on Add Build Phase > Add Copy Headers. 

**Xcode 5:**
Add Build Phases from the menu. Click on Editor > Add Build Phase -> Add Copy Headers Build Phase. Note: If the menu options are grayed out, you'll need to click on the whitespace below the Build Phases to regain focus and retry.

**Xcode 6:**
Add Build Phases from the menu. Click on Editor > Add Build Phase -> Add Headers Build Phase. Note: If the menu options are grayed out, you'll need to click on the whitespace below the Build Phases to regain focus and retry.


You'll see 3 sections for Public, Private, and Project headers. To modify the scope of any header, drag and drop the header files between the sections. Alternatively you can open the Project Navigator and select the header. Next expand the Utilities pane for the File Inspector.
![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/utilitiesbutton.png)
(Cmd+Option+0).

Look at the "Target Membership" group and ensure that the checkbox next to the .h file is checked.
Change the scope of the header from "Project" to "Public". You might have to uncheck and check the box to get the dropdown list. This will ensure that the header gets
copied to the correct location in the copy headers phase.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/publicheaders.png)

### Step 3: Update the Public Headers Location

By default the static library project will copy private and public headers to the same folder:
`/usr/local/include`. To avoid mistakenly copying private headers to our framework we want to ensure
that our public headers are copied to a separate directory, e.g. `$(PROJECT_NAME)Headers`. To change this setting,
select the project in the Project Navigator and then click the "Build Settings" tab. Search for "public
headers" and then set the "Public Headers Folder Path" to "$(PROJECT_NAME)Headers" for all configurations.
If you are working with multiple Frameworks make sure that this folder is unique.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/publicheadersconfig.png)

### Ongoing Step: Adding New Sources to the Framework

Whenever you add new source to the framework you must decide whether to expose the .h publicly or
not. To modify a header's scope you will follow the same process as Step 2. By default a header's
scope will be "Project", meaning it will not be copied to the framework's public headers.

#### An Important Note on Categories

Using a category should be a **necessity**, not a convenience, when distributing a framework.

Frameworks, by their very nature, obscure most implementation details, very likely leading to severe run-time tomfoolery as symbols get overwritten and your client's app starts performing in wonderfully novel ways (much to their users' chagrin).

If you **absolutely** ***must*** use categories, please check out the [FAQ](#faq) in order to avoid having your clients encounter linker problems when attempting to use them.

### Step 4: Disable Code Stripping

We do not want to strip any code from the library; we leave this up to the application that is
linking to the framework. To disable code stripping we must modify the following configuration
settings:

    "Dead Code Stripping" => No (for all settings)
    "Strip Debug Symbols During Copy" => No (for all settings)
    "Strip Style" => Non-Global Symbols (for all settings)

### Step 5: Enable all architecture support

We want our framework able to work with all device architectures. To do so, change this in your project file (not your target files !):
    "Build Active Architecture Only" => No (for all settings)

### Step 6: Prepare the Framework for use as a Dependent Target

In order to use the static library as though it were a framework we're going to generate the basic
skeleton of the framework in the static library target. To do this we'll include a simple post-build
script. Add a post-build script by selecting your project in the Project Navigator, selecting the target, and then the
"Build Phases" tab. 

**Xcode 4.X:** Click Add Build Phase > Add Run Script

**Xcode 5:** Select Editor menu > Add Build Phase > Add Run Script Build Phase

Paste the following script in the source portion of the run script build phase. You can rename the phase by clicking
the title of the phase (I've named it "Prepare Framework", for example).

#### prepare_framework.sh

```bash
set -e

mkdir -p "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Versions/A/Headers"

# Link the "Current" version to "A"
/bin/ln -sfh A "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Versions/Current"
/bin/ln -sfh Versions/Current/Headers "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Headers"
/bin/ln -sfh "Versions/Current/${PRODUCT_NAME}" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/${PRODUCT_NAME}"

# The -a ensures that the headers maintain the source modification date so that we don't constantly
# cause propagating rebuilds of files that import these headers.
/bin/cp -a "${TARGET_BUILD_DIR}/${PUBLIC_HEADERS_FOLDER_PATH}/" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.framework/Versions/A/Headers"

```

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/prepareframework.png)

This will generate the following folder structure:

```
-- Note: "->" denotes a symbolic link --

Serenity.framework/
  Headers/ -> Versions/Current/Headers
  Serenity -> Versions/Current/Serenity
  Versions/
    A/
      Headers/
        Serenity.h
        Widget.h
    Current -> A
```

Try building your project now and look at the build products directory (usually
`~/Library/Developer/Xcode/DerivedData/<ProjectName>-<gibberish>/Build/Products/...`). You should
see a `libSerenity.a` static library, a `Headers` folder, and a `Serenity.framework` folder that
contains the basic skeleton of your framework.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/buildphase1.png)

### Step 7: Enable bitcode (Optional)

**Xcode 7.x** is required for bitcode support.

To include bitcode in your framework, just add **-fembed-bitcode** flag to the static
library C flags.

<a name="framework_distribution_target">
  
Create the Framework Distribution Target
----------------------------------------

When actively developing the framework we only care to build the platform that we're testing on. For
example, if we're testing on the iPhone simulator then we only need to build the i386 platform.

This changes when we want to distribute the framework to third party developers. The third-party
developers don't have the option of rebuilding the framework for each platform, so we must provide
what is called a "fat binary" version of the static library that is comprised of the possible
platforms. These platforms include: i386, armv6, armv7, and armv7s.

To generate this fat binary we're going to build the static library target for each platform.

### Step 1: Create an Aggregate Target

Click File > New Target > iOS > Other and create a new Aggregate target. Title it something like "Framework".

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/aggregatetarget.png)

### Step 2: Add the Static Library as a Dependent Target

Add the static library target to the "Target Dependencies".

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/targetdependencies.png)

### Step 3: Build the Other Platform

To build the other platform we're going to use a "Run Script" phase to execute some basic commands.
Add a new "Run Script" build phase to your aggregate target and paste the following code into it.

#### build_framework.sh

```bash
set -e
set +u
# Avoid recursively calling this script.
if [[ $SF_MASTER_SCRIPT_RUNNING ]]
then
    exit 0
fi
set -u
export SF_MASTER_SCRIPT_RUNNING=1

SF_TARGET_NAME=${PROJECT_NAME}
SF_EXECUTABLE_PATH="lib${SF_TARGET_NAME}.a"
SF_WRAPPER_NAME="${SF_TARGET_NAME}.framework"

# The following conditionals come from
# https://github.com/kstenerud/iOS-Universal-Framework

if [[ "$SDK_NAME" =~ ([A-Za-z]+) ]]
then
    SF_SDK_PLATFORM=${BASH_REMATCH[1]}
else
    echo "Could not find platform name from SDK_NAME: $SDK_NAME"
    exit 1
fi

if [[ "$SDK_NAME" =~ ([0-9]+.*$) ]]
then
    SF_SDK_VERSION=${BASH_REMATCH[1]}
else
    echo "Could not find sdk version from SDK_NAME: $SDK_NAME"
    exit 1
fi

if [[ "$SF_SDK_PLATFORM" = "iphoneos" ]]
then
    SF_OTHER_PLATFORM=iphonesimulator
else
    SF_OTHER_PLATFORM=iphoneos
fi

if [[ "$BUILT_PRODUCTS_DIR" =~ (.*)$SF_SDK_PLATFORM$ ]]
then
    SF_OTHER_BUILT_PRODUCTS_DIR="${BASH_REMATCH[1]}${SF_OTHER_PLATFORM}"
else
    echo "Could not find platform name from build products directory: $BUILT_PRODUCTS_DIR"
    exit 1
fi

# Build the other platform.
xcrun xcodebuild -project "${PROJECT_FILE_PATH}" -target "${TARGET_NAME}" -configuration "${CONFIGURATION}" -sdk ${SF_OTHER_PLATFORM}${SF_SDK_VERSION} BUILD_DIR="${BUILD_DIR}" OBJROOT="${OBJROOT}" BUILD_ROOT="${BUILD_ROOT}" SYMROOT="${SYMROOT}" $ACTION

# Smash the two static libraries into one fat binary and store it in the .framework
xcrun lipo -create "${BUILT_PRODUCTS_DIR}/${SF_EXECUTABLE_PATH}" "${SF_OTHER_BUILT_PRODUCTS_DIR}/${SF_EXECUTABLE_PATH}" -output "${BUILT_PRODUCTS_DIR}/${SF_WRAPPER_NAME}/Versions/A/${SF_TARGET_NAME}"

# Copy the binary to the other architecture folder to have a complete framework in both.
cp -a "${BUILT_PRODUCTS_DIR}/${SF_WRAPPER_NAME}/Versions/A/${SF_TARGET_NAME}" "${SF_OTHER_BUILT_PRODUCTS_DIR}/${SF_WRAPPER_NAME}/Versions/A/${SF_TARGET_NAME}"

```

#### Important Notes

The above script assumes that your library name matches your project name in the following line:

```bash
SF_TARGET_NAME=${PROJECT_NAME}
```

If this is not the case (e.g. your xcode project is named SerenityFramework and the target name is
Serenity) then you need to explicitly set the target name on that line. For example:

```bash
SF_TARGET_NAME=Serenity
```

If you are using Cocoapods, you need to build the workspace instead of the project. Assuming your 
Scheme matches your aggregate target name, change the `xcrun xcodebuild` line to:

```bash
xcrun xcodebuild ONLY_ACTIVE_ARCH=NO -workspace "${PROJECT_DIR}/${PROJECT_NAME}.xcworkspace" -scheme "${TARGET_NAME}" -configuration "${CONFIGURATION}" -sdk ${SF_OTHER_PLATFORM}${SF_SDK_VERSION} BUILD_DIR="${BUILD_DIR}" OBJROOT="${OBJROOT}" BUILD_ROOT="${BUILD_ROOT}" SYMROOT="${SYMROOT}" $ACTION
```

### Step 4: Build and Verify

You now have everything set up to build a distributable .framework to third-party developers. Try
building the aggregate target. Once it's done, expand the Products folder in Xcode, right click the
static library and click "Show in Finder". If this doesn't open Finder to where the static library
exists then try opening
`~/Library/Developer/Xcode/DerivedData/<project name>/Build/Products/Debug-iphonesimulator/`.

Within this folder you will see your .framework folder.

Verify that your framework includes all of the architectures that are available by running the
`file` command on your framework's static library:

```bash
lipo -info Serenity.framework/Serenity
```

You should see output resembling:

```bash
Architectures in the fat file: Serenity.framework/Serenity are: i386 x86_64 armv7 armv7s arm64
```

If you don't see all of the architectures listed, make sure that you're looking at the right
framework output. If you're building with the Simulator as your target, the correct framework
will be in the -iphonesimulator folder. Sometimes it can help to delete the Debug- and Release-
folders to ensure that you're getting a truly clean build.

Once you've verified that the framework includes all of the architectures, you can now move
the .framework elsewhere, zip it up, upload it, and distribute it to your third-party developers.

<a name="resources" />

Resources and Bundles
=====================

To distribute resources with a framework, we are going to provide the developer with a separate
.bundle that contains all of the strings and resources. This distribution method provides a number
of advantages over including the resources in the .framework itself.

- Encapsulation of resources. We can scope resource loading to our framework's bundle.
- Easy to add bundles to projects.
- The developer doesn't have to copy the entire .framework into their application.

The hard part about bundles is creating the target. Xcode's bundle target doesn't actually create a
loadable bundle object, so we have to do some post-build massaging of the bundle. It's important
that we create a bundle target because we need to create the bundle using the Copy Bundle Resources
phase that will correctly compile .xib files (a Copy Files phase does not accomplish this!).

### Step 1: Create the Bundle Target

In the framework project, create a new bundle target. Click on File > New > Target > OS X > Bundle. You will need to name the bundle something
different from your framework name or Xcode will not let you create the target. I've named the target SerenityResources. We will rename the output of the target to Serenity.bundle in a following
step.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/newbundletarget.png)

Ensure that the Framework setting is set to "Core Foundation".

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/newbundletarget2.png)

### Step 2: Clean up the Bundle Target Settings

By default the bundle will only show build settings for Mac OS X. It doesn't really matter what it
builds for because the bundle isn't actually going to have any code in it, but I prefer to have
things nice and consistent. Open the bundle target settings and delete the settings for
Architectures, Base SDK, and Build Active Architecture Only.

**Xcode 5:** Deleting a build setting will reset it to the Project's build setting. It should switch from OS X to iOS.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/bundlesettings.png)

This is also when you should change your bundle target's product name to the name of your framework
rather than the target name. Click on your project in the Project Navigator and then select
the bundle target. Click Build Settings, search for "Product Name", and then replace
the value of Product Name with the name of your framework (e.g. $(TARGET_NAME) replaced by Serenity)

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/serenityproductname.png)

### Step 3: Remove HIDPI Mac OS X Build Setting
We created a OS X Bundle and it includes and option to merge HIDPI (retina and non-retina) art assets into a .tiff file. You don't want this behavior and need to disable it, or you will be unable to load your image assets from the bundle.

In the Bundle target go to Build Settings and search for `COMBINE_HIDPI_IMAGES` and delete the user defined setting. When you build, verify that your @2x.png and .png images are all in the bundle.

![Delete the COMBINE_HIDPI_IMAGES setting](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/delete_combine_hidpi.png)

### Ongoing Step: Add Resources to the Bundle Target Copy Files Phase

Whenever you add new resources that you want to include with your framework you need to add it to
the bundle target that you created.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/newbundleresource.png)

### Step 4: Add the Bundle Target to your Aggregate Target

Whenever we build the framework for distribution we likely also want to build the bundle. Add the
bundle target to your aggregate target's dependencies.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/bundledependency.png)

### Step 5: Loading Bundle Resources

In order to load bundle resources, we must first ask the third-party developer to add the .bundle to
their application. To do so they will simply drag the .bundle that you distributed with the
.framework to their project and ensure that it is copied in the copy files phase of their app
target.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/addbundle.png)

To load resources from the bundle we will use the following code:

```obj-c
// Load the framework bundle.
+ (NSBundle *)frameworkBundle {
  static NSBundle* frameworkBundle = nil;
  static dispatch_once_t predicate;
  dispatch_once(&predicate, ^{
    NSString* mainBundlePath = [[NSBundle mainBundle] resourcePath];
    NSString* frameworkBundlePath = [mainBundlePath stringByAppendingPathComponent:@"Serenity.bundle"];
    frameworkBundle = [[NSBundle bundleWithPath:frameworkBundlePath] retain];
  });
  return frameworkBundle;
}

[UIImage imageWithContentsOfFile:[[[self class] frameworkBundle] pathForResource:@"image" ofType:@"png"]];
```

You can see an example of loading a resource from within the framework in the Widget object in the
included Serenity framework.

**Xcode 5:** Do not use the Asset Catalog for any resources within a bundle. On an iOS 7.0 only project, a bug causes the pathForResource method to return nil. 

<a name="third_parties" />

Adding the Framework to a Third-Party Application
=================================================

> View a sample project that shows the result of following these steps in the `sample/ThirdParty`
> directory.

This is the easy part (and what your third-party developers will have to do). Simply drag the
.framework to your application's project, ensuring that it's being added to the necessary targets.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/thirdparty.png)

Import your framework header and you're kickin' ass.

```obj-c
#import <Serenity/Serenity.h>
```

### Resources

If you're distributing resources with your framework then you will also send the .bundle file to the
developers. The developer will then drag the .bundle file into their application and ensure that
it's added to the application target.

<a name="first_parties" />

Developing the Framework as a Dependent Project
===============================================

> View a sample project that shows the result of following these steps in the `sample/DependentApp`
> directory.

When developing the framework you want to minimize build times while ensuring that your experience
roughly matches that of your third-party developers. We achieve this balance by only building the
static library but treating the static library as though it were a framework.

### Step 1: Add the Framework Project to your Application Project

To add the framework as a dependent target in your application, from Finder drag the framework's .xcodeproj to
Xcode and drop it in your application's frameworks folder. This will add a reference to the
framework's xcodeproj folder. 

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/dependentapp.png)

### Step 2: Make the Framework Static Library Target a Dependency

Once you've added the framework project to your app you can add the static library product as a
dependency. Select your project in the Project Navigator and open the "Build Phases" tab. Expand
the "Target Dependencies" group and click the + button. Select the static library target and click
"Add".

**Note:** Close your Static Library Project or the dependencies will not appear in the list. You can only have one instance of an Xcode project open.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/addtarget.png)

### Step 3: Link your Application with the Framework Static Library

In order to use the framework's static library we must link it into the application. Expand the
"Link Binary With Libraries" phase and click the + button. Select the `.a` file that's exposed by
your framework's project and then click add.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/linker.png)

### Step 4: Import the Framework Header

You now simply need to import the framework header somewhere in your project. I generally prefer
the pch so that I don't have to clutter up my application's source with framework headers, but you
can obviously choose whatever practice suits your needs.

```obj-c
#import <Serenity/Serenity.h>
```

### Step 4-b: Adding Resources

If you are developing resources for your framework you can also add the bundle target as a
dependency.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/bundledependency2.png)

You must then add the bundle to the Copy Bundle Resources phase of your application by expanding
the products folder of your framework product and dragging the .bundle into that section.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/bundlecopy.png)

### Step 5: Check Dependent Target Build Settings

Set the setting `Skip Install` to `Yes` for any static library or bundle target that you create. Check all the targets that are dependencies of your application project. If the option is `No` then you will be unable to build an archive of the project containing the target dependencies. Xcode will create a Generic Xcode Archive, which cannot be shared adhoc, validated, or submitted.

![](https://github.com/jverkoey/iOS-Framework/raw/master/gfx/skip_install.png)

### Step 6: Build and Test

Build your application and verify a couple things:

- Your framework should be built before your application.
- Your framework should be linked into the application.
- You shouldn't get any compiler or linker errors.

<a name="faq" />

FAQ
===

How do I resolve 'unrecognized selector sent to instance' linker errors?
------------------------------------------------------------------------

- **The recommended solution** is to use [NimbusKitBasics' NI_FIX_CATEGORY_BUG](https://github.com/NimbusKit/basics#avoid-requiring-the--all_load-and--force_load-flags) whenever possible. This solution minimizes the amount of your framework that will need to be linked into the client's app binary.
- [Breakdown of solutions](http://stackoverflow.com/a/22264650/65455) from [Mecki](http://stackoverflow.com/users/15809/mecki) on stackoverflow.

How do I include Third-Party Libraries in my Framework?
-------------------------------------------------------

Don't.

Ok, you can, but it's touch to do correctly - and it's really important that you do it correctly.

The scenario you want to avoid is the following:

- You've linked some third-party library in your code (e.g. [NimbusKit's Markdown](https://github.com/nimbuskit/markdown)).
- A client using your framework also wants to use NimbusKit's Markdown.
- Their app fails to build due to duplicate symbol linker errors.
- Client gets incredibly frustrated with your framework and uses something else.

Solutions, in order of easiest-to-most-difficult:

### Pure framework build (no third-party libraries included) + library source distribution

Bundle any libraries that your framework uses alongside your framework when you distribute it (e.g. distribute a zip file with your built .framework and a third-party folder containing the source for all libraries used). Make it clear in your setup guide that the additional libraries will also need to be compiled into the client's app.

This:

- gives the client the flexibility to use their own version of the library;
- encourages proper attribution and license redistribution of any open source code you're using;
- and, most importantly, ensures that the client will not encounter duplicate symbol linker errors.

### Symbol Prefixing

This is hard to do correctly and requires meticulous ongoing care to ensure that no symbols ever slip through the build process.

This solution allows you to completely guarantee that a given version of a third-party library will be used by your framework. It also allows you to distribute a single .framework, easing the setup and versioning process.

Some approaches to symbol prefixing:

- High level overview by [featherless](http://twitter.com/featherless) on StackOverflow: [http://stackoverflow.com/questions/11512291/prefix-static-library-ios/19341366#19341366](http://stackoverflow.com/questions/11512291/prefix-static-library-ios/19341366#19341366).
- [Avoiding Dependency Collisions in an iOS Library](http://pdx.esri.com/blog/2013/12/13/namespacing-dependencies/) on esri.com.

<a name="license" />

License
=======

Except as otherwise noted, the content of this page is licensed under the Creative Commons
Attribution 3.0 Unported License, and code samples are licensed under the Apache 2.0 License.

To view a copy of this license, visit httip://creativecommons.org/licenses/by/3.0/ or send a letter
to Creative Commons, 444 Castro Street, Suite 900, Mountain View, California, 94041, USA.
