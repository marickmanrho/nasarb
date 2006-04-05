#!/usr/bin/env ruby
#
# $Id$
#
# Generates a Fortran 90 code which runs all the mobility
# test suites in this directory (or only those test suites
# specified on the command line).

#######################
#require 'FTKfunctions'

class Compiler
 attr_reader :name
 def initialize name=ENV['F9X']
  errorMessage = <<-ENVIRON

Fortran compiler environment variable 'F9X' not set:

 for bourne-based shells: export F9X=lf95 (in .profile)
      for c-based shells: setenv F9X lf95 (in .login)
             for windows: set F9X=C:\Program Files\lf95 (in autoexec.bat)

  ENVIRON
  raise(errorMessage) unless @name = name
 end
end

def requestedModules(moduleNames)
 if (moduleNames.empty?)
  moduleNames = Dir["*MT.ftk"].each { |mod| mod.chomp! "MT.ftk" }
 end
 moduleNames
end

def ftkExists?(moduleName)
 File.exists? moduleName+"MT.ftk"
end

def parseCommandLine

 moduleNames = requestedModules(ARGV)

 if moduleNames.empty?
  raise "   *Error: no test suites found in this directory"
 end

 moduleNames.each do |mod|
  unless ftkExists?(mod) 
   errorMessage = <<-FTKDOESNOTEXIST
 Error: could not find test suite #{mod}MT.ftk
 Test suites available in this directory:
 #{requestedModules([]).join(' ')}

 Usage: #{File.basename $0} [test names (w/o MT.ftk suffix)]
   FTKDOESNOTEXIST
   raise errorMessage
  end
 end

end

def writeTestRunner testSuites

 File.delete("TestRunner.f90") if File.exists?("TestRunner.f90")
 testRunner = File.new "TestRunner.f90", "w"

 testRunner.puts <<-HEADER
! TestRunner.f90 - runs Fortran mobility test suites
!
! [Dynamically generated by #{File.basename $0} Ruby script #{Time.now}.]

program TestRunner

 HEADER

 testSuites.each { |testSuite| testRunner.puts " use #{testSuite}MT" }

 testRunner.puts <<-DECLARE

 implicit none

 integer :: numTests, numAsserts, numAssertsTested, numFailures
 DECLARE

 testSuites.each do |testSuite|
  testRunner.puts <<-TRYIT

 print *, ""
 print *, "#{testSuite} test suite:"
 call MT#{testSuite}( numTests, &
        numAsserts, numAssertsTested, numFailures )
 print *, "Passed", numAssertsTested, "of", numAsserts, &
          "possible asserts comprising", &
           numTests-numFailures, "of", numTests, "tests." 
  TRYIT
 end

 testRunner.puts "\n print *, \"\""
 testRunner.puts "\nend program TestRunner"
 testRunner.close
 File.chmod(0444,"TestRunner.f90")
end

def syntaxError( message, testSuite )
 raise "\n   *Error: #{message} [#{testSuite}MT.ftk:#$.]\n\n"
end

def warning( message, testSuite )
 $stderr.puts "\n *Warning: #{message} [#{testSuite}MT.ftk:#$.]"
end

def compileTests testSuites
 require 'Depend'

 puts "computing dependencies"
 dependencies = Depend.new(['.', '../LibF90', '../PHYSICS_DEPS'])
 puts "locating associated source files and sorting for compilation"
 requiredSources = dependencies.required_source_files('TestRunner.f90')

 puts compile = "#{ENV['F9X']} #{ENV['F9X_LDFLAGS']} -o TestRunner \\\n  #{requiredSources.join(" \\\n  ")}"

 raise "Compile failed." unless system(compile)

end

# set some regular expressions:
$keyword = /(begin|end)(Setup|Teardown|Test)|Is(RealEqual|Equal|False|True|EqualWithin)\(.*\)/i
$commentLine = /^\s*!/

####################
#require 'TestSuite'

###################
# require 'Asserts'

module Asserts

 $assertRegEx = /Is(RealEqual|False|True|EqualWithin|Equal)\(.*\)/i

 def istrue(line)
  line=~/\((.+)\)/
  @type = 'IsTrue'
  @condition = ".not.(#$1)"
  @message = "\"#$1 is not true\""
  syntaxError("invalid body for #@type",@suiteName) unless $1=~/\S+/
  writeAssert
 end

 def isfalse(line)
  line=~/\((.+)\)/
  @type = 'IsFalse'
  @condition = "#$1"
  @message = "\"#$1 is not false\""
  syntaxError("invalid body for #@type",@suiteName) unless $1=~/\S+/
  writeAssert
 end

 def isrealequal(line)
  line=~/\(([^,]+),(.+)\)/
  @type = 'IsRealEqual'
  @condition = ".not.(#$1+2*spacing(real(#$1)).ge.#$2 &\n             .and.#$1-2*spacing(real(#$1)).le.#$2)"
  @message = "\"#$2 (\",#$2,\") is not\",#$1,\"within\",2*spacing(real(#$1))"
  syntaxError("invalid body for #@type",@suiteName) unless $&
  writeAssert
 end

 def isequalwithin(line)
  line=~/\(([^,]+),(.+),(.+)\)/
  @type = 'IsEqualWithin'
  @condition = ".not.(#$2+#$3.ge.#$1 &\n             .and.#$2-#$3.le.#$1)"
  @message = "\"#$1 (\",#$1,\") is not\",#$2,\"within\",#$3"
  syntaxError("invalid body for #@type",@suiteName) unless $&
  writeAssert
 end

 def isequal(line)
  line=~/\((\w+\(.*\)|[^,]+),(.+)\)/
  @type = 'IsEqual'
  @condition = ".not.(#$1==#$2)"
  @message = "\"#$1 (\",#$1,\") is not\", #$2"
  syntaxError("invalid body for #@type",@suiteName) unless $&
  writeAssert
 end

 def writeAssert
  <<-OUTPUT

  ! #@type assertion
  numAsserts = numAsserts + 1
  if (noAssertFailed) then
    if (#@condition) then
      print *, " *#@type failed* in test #@testName &
                         &[#{@suiteName}MT.ftk:#{@lineNumber.to_s}]"
      print *, "  ", #@message
      print *, ""
      noAssertFailed = .false.
      numFailures    = numFailures + 1
    else
      numAssertsTested = numAssertsTested + 1
    endif
  endif
  OUTPUT
 end

end

######################

class TestSuite < File

 include Asserts

 def initialize suiteName
  @lineNumber = 'blank'
  @suiteName = suiteName
  return nil unless ftkExists?(suiteName)
  File.delete(suiteName+"MT.f90") if File.exists?(suiteName+"MT.f90")
  super(suiteName+"MT.f90","w")
  @tests, @setup, @teardown = Array.new, Array.new, Array.new
  topWrapper
  expand
  close
 end

 def topWrapper
  puts <<-TOP
! #{@suiteName}MT.f90 - a Fortran mobility test suite for #{@suiteName}.f90
!
! [dynamically generated from #{@suiteName}MT.ftk
!  by #{File.basename $0} Ruby script #{Time.now}]

module #{@suiteName}MT

 use #{@suiteName}

 implicit none

 private

 public :: MT#{@suiteName}

 logical :: noAssertFailed

 integer :: numTests          = 0
 integer :: numAsserts        = 0
 integer :: numAssertsTested  = 0
 integer :: numFailures       = 0

  TOP
 end

 def expand
 
  ftkFile = @suiteName+"MT.ftk"
  $stderr.puts "parsing #{ftkFile}"
   
  ftk = IO.readlines(ftkFile)
  @ftkTotalLines = ftk.length

  while (line = ftk.shift) && line !~ $keyword
   puts line
  end

  ftk.unshift line

  puts " contains\n\n"

  while (line = ftk.shift)
   case line
   when $commentLine
    puts line
   when /beginSetup/i
    addtoSetup ftk
   when /beginTeardown/i
    addtoTeardown ftk
   when /XbeginTest\s+(\w+)/i
    ignoreTest($1,ftk)
   when /beginTest\s+(\w+)/i
    aTest($1,ftk)
   when /beginTest/i
    syntaxError "no name given for beginTest", @suiteName
   when /end(Setup|Teardown|Test)/i
    syntaxError "no matching begin#$1 for an #$&", @suiteName
   when $assertRegEx
    syntaxError "#$1 assert not in a test block", @suiteName
   else
    puts line
   end
  end # while

  $stderr.puts "completed #{ftkFile}"

 end

 def addtoSetup ftk
  while (line = ftk.shift) && line !~ /endSetup/i
   @setup.push line
  end
 end

 def addtoTeardown ftk
  while (line = ftk.shift) && line !~ /endTeardown/i
   @teardown.push line
  end
 end

 def ignoreTest testName, ftk
  warning("Ignoring test: #{testName}", @suiteName)
  line = ftk.shift while line !~ /endTest/i
 end

 def aTest testName, ftk
  @testName = testName
  @tests.push testName
  syntaxError("test name #@testName not unique",@suiteName) if (@tests.uniq!)

  puts " subroutine Test#{testName}\n\n"

  numOfAsserts = 0
  
  while (line = ftk.shift) && line !~ /endTest/i
   case line
   when $commentLine
    puts line
   when /Is(RealEqual|False|True|EqualWithin|Equal)/i
    @lineNumber = @ftkTotalLines - ftk.length
    numOfAsserts += 1
    puts send( $&.downcase!, line )
   else
    puts line
   end
  end
  warning("no asserts in test", @suiteName) if numOfAsserts == 0

  puts "\n  numTests = numTests + 1\n\n"
  puts " end subroutine Test#{testName}\n\n"
 end

 def close
  puts "\n subroutine Setup"
  puts @setup
  puts "  noAssertFailed = .true."
  puts " end subroutine Setup\n\n"

  puts "\n subroutine Teardown"
  puts @teardown
  puts " end subroutine Teardown\n\n"

  puts <<-NEXTONE

 subroutine MT#{@suiteName}( nTests, nAsserts, nAssertsTested, nFailures )

  integer :: nTests
  integer :: nAsserts
  integer :: nAssertsTested
  integer :: nFailures

  continue
  NEXTONE

  @tests.each do |testName|
   puts "\n  call Setup"
   puts "  call Test#{testName}"
   puts "  call Teardown"
  end

  puts <<-LASTONE

  nTests          = numTests
  nAsserts        = numAsserts
  nAssertsTested  = numAssertsTested
  nFailures       = numFailures

 end subroutine MT#{@suiteName}

end module #{@suiteName}MT
  LASTONE
  super
  File.chmod(0444,@suiteName+"MT.f90")
 end

end

####################
# main code follows

def runAllFtks

 Compiler.new # a test for compiler env set (remove this later)

 writeTestRunner(testSuites = parseCommandLine)

 # convert each *MT.ftk file into a pure Fortran9x file:

 threads = Array.new

 testSuites.each do |testSuite|
  threads << Thread.new(testSuite) do |testSuite|
   testSuiteF90 = TestSuite.new(testSuite)
  end
 end
 
 threads.each{ |thread| thread.join }
 
 compileTests testSuites

 raise "Failed to execute TestRunner" unless system("./TestRunner")
 
end

if $0 == __FILE__
 $:.push File.join(Dir.pwd.split('FUN3D').first,'FUN3D','Ruby')
 runAllFtks 
end