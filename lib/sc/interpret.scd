var tab = [$\\,$\\,$t].as(String),
    nl = [$\\,$\\,$n].as(String),
    toJSON = IdentityDictionary.new,
    errorToJSON = IdentityDictionary.new;

Library.put(\supercolliderjs, \interpret,
  { arg guid, escapedCode, executingPath, returnResultAsString=true, reportError=true, getBacktrace=false;

    var code = escapedCode.replace("__NL__", Char.nl),
        compiled,
        result,
        error,
        saveExecutingPath = thisProcess.nowExecutingPath;

    code = code.replace("__SLASH__", $\\);

    thisProcess.nowExecutingPath = executingPath;

    // capture compile errors, stdout
    "\nSUPERCOLLIDERJS:%:CAPTURE:START\n".format(guid).postln;
    compiled = code.compile;

    if(compiled.isNil, {
      "\nSUPERCOLLIDERJS:%:CAPTURE:END".format(guid).postln;
      Library.at(\supercolliderjs, \return)
        .value(guid, "SyntaxError", nil);
    }, {
      {
        result = compiled.value();
      }.try({ arg err;
        err.path = executingPath ? guid;
        error = errorToJSON.at(\getData).value(err, getBacktrace, compiled);

        // classic mode
        if(reportError.asBoolean, {
          err.reportError;
        });
      });
      "\nSUPERCOLLIDERJS:%:CAPTURE:END".format(guid).postln;
      if(error.notNil, {
        Library.at(\supercolliderjs, \return)
          .value(guid, "Error", error);
      }, {
        Library.at(\supercolliderjs, \return)
          .value(guid, "Result", if(returnResultAsString ? true, { result.asString }, { result }));
      });
    });

    thisProcess.nowExecutingPath = saveExecutingPath;
  });

Library.put(\supercolliderjs, \return,
  { arg guid, type, object;
    // posts to STDOUT
    var json = toJSON.at(\stringify).value(object);
    "\nSUPERCOLLIDERJS:%:START:%".format(guid, type).postln;
    // sclang screws up when posting long lines in a single chunk
    json.clump(2048).do { arg chunk;
      "SUPERCOLLIDERJS:%:CHUNK:%".format(guid, chunk).postln;
    };
    "SUPERCOLLIDERJS:%:END:%".format(guid, type).postln;
  });


/******************    errors    *****************************************/

errorToJSON = (
  getData: { arg err, getBacktrace=false, compiledFunc;
    var data = ();
    err.class.superclassesDo({ arg class;
      var handler = errorToJSON.at(class.name);
      if(handler.notNil, {
        data.putAll(handler.value(err));
      });
    });
    if(getBacktrace, {
      data['backtrace'] = errorToJSON.at(\getBacktrace).value(err, compiledFunc);
    });
    data
  },
  obj: { arg obj, deep=false;
    var dd, asString, class = obj.class;
    if(class.class === Class or: {class === Main}, {
      deep = false;
    });
    if(class === String or: (class === Symbol), {
      asString = obj.asCompileString;
    }, {
      {
        asString = obj.asString;
      }.try({
        asString = "(asString error)";
      });
    });
    dd = (
      class: obj.class,
      asString: asString
    );
    if(class === Function, {
      dd.sourceCode = obj.def.sourceCode
    });
    if(deep, {
      dd.vars = (obj.class.instVarNames ? []).collect({ arg v, i;
        (
          name: v,
          value: errorToJSON.at(\obj).value(obj.instVarAt(i), false)
        )
      });
    });
    dd
  },
  frameContext: { arg frame;
    // 'context' points to another DebugFrame for the frame lexically enclosing this one.
    // This searches up the context chain for the enclosing method
    // where the function was defined.
    var def;
    if(frame.isNil, {
      nil
    }, {
      def = frame.functionDef;
      if(def.class === Method, {
        if(def.ownerClass === Interpreter, {
          nil
        }, {
          (
            class: def.ownerClass,
            method: def.name,
            file: def.filenameSymbol,
            charPos: def.charPos,
            source: def.sourceCode
          )
        });
      }, {
        if(frame.context.isNil, {
          nil
        }, {
          errorToJSON.at('frameContext').value(frame.context);
        })
      })
    });
  },
  getBacktrace: { arg err, compiledFunc;
    var out, currentFrame, def, ownerClass, methodName, callerAddress,
      startAtDef, stopAtDef, addingFrame = false;
    out = [];

    currentFrame = err.protectedBacktrace ?? { err.getBackTrace };

    // 'caller' points to another DebugFrame for the caller to this function.
    callerAddress = { arg caller;
      caller !? { caller.address.asString }
    };
    // the source code to interpret compiled to a function
    if(compiledFunc.notNil, {
      stopAtDef = compiledFunc.def;
    /*}, {
      // out of band thrown Error
      startAtDef = Object.findMethod('throw');*/
    });

    while({
      currentFrame.notNil and: {
        currentFrame.functionDef !== stopAtDef
      }
    }, {
      var vv;
      def = currentFrame.functionDef;

      if(def.isKindOf(Method), {
        ownerClass = def.ownerClass;
        methodName = def.name;
        vv = (
          type: "Method",
          class: ownerClass,
          method: methodName,
          file: def.filenameSymbol,
          charPos: def.charPos,
          source: def.sourceCode,
          address: currentFrame.address.asString,
          caller: callerAddress.(currentFrame.caller)
        );
      }, {
         vv = (
          type: "Function",
          address: currentFrame.address.asString,
          source: def.sourceCode,
          caller: callerAddress.(currentFrame.caller),
          // maybe indicate if its an inner function
          context: errorToJSON.at('frameContext').value(currentFrame.context)
        );
      });

      vv[\args] = def.argNames.collect({ |name, i|
        (
            name: name,
            value: errorToJSON.at(\obj).value(currentFrame.args[i], true)
        )
      });
      vv[\vars] = def.varNames.collect({ |name, i|
        (
            name: name,
            value: errorToJSON.at(\obj).value(currentFrame.vars[i], true)
        )
      });

      out = out.add(vv);
      currentFrame = currentFrame.caller;
    });

    out
  },
  // error classes
  Exception: { arg err;
    (
        class: err.class,
        what: err.what,
        path: err.path,
        errorString: err.errorString
    )
  },
  MethodError: { arg err;
    (
      receiver: errorToJSON.at(\obj).value(err.receiver)
    )
  },
  PrimitiveFailedError: { arg err;
    (
      failedPrimitiveName: err.failedPrimitiveName
    )
  },
  SubclassResponsibilityError: { arg err;
    (
      method: (
        name: err.method.name,
        class: err.class
      )
    )
  },
  ShouldNotImplementError: { arg err;
    (
      method: (
        name: err.method.name,
        class: err.class
      )
    )
  },
  DoesNotUnderstandError: { arg err;
    (
      selector: err.selector,
      args: err.args.collect({ arg a; errorToJSON.at(\obj).value(a)})
    )
  },
  OutOfContextReturnError: { arg err;
    (
      method: (
        name: err.method.name,
        class: err.method.ownerClass
      ),
      result: errorToJSON.at(\obj).value(err.result)
    )
  },
  ImmutableError: { arg err;
    (
      value: errorToJSON.at(\obj).value(err.value)
    )
  },
  DeprecatedError: { arg err;
    (
      method: (
        name: err.method.name,
        class: err.method.ownerClass
      ),
      alternateMethod: (
        name: err.alternateMethod.name,
        class: err.alternateMethod.ownerClass
      )
    )
  }
);

Library.put(\supercolliderjs, \errorToJSON, errorToJSON);


/********************   a portable JSON stringify ************************/

toJSON.putPairs([

  \stringify, { arg object;
    toJSON.at(\encoderFor).value(object.class).value(object);
  },
  \encoderFor, { arg class;
    toJSON.at(class) ?? {
      toJSON.at(\encoderFor).value(class.superclass)
    };
  },

  Object, { arg data;
    data.asCompileString
  },
  String, { arg obj;
    obj.asCompileString.reject(_.isControl).replace(Char.nl, nl).replace(Char.tab, tab);
  },
  Symbol, { arg obj;
    toJSON.at(\stringify).value(obj.asString);
  },
  Class, { arg obj;
    toJSON.at(\stringify).value(obj.name.asString);
  },
  Dictionary, { arg obj;
    var out = List.new;
    obj.keysValuesDo({ arg key, value;
        out.add(key.asString.asCompileString ++ ":" + toJSON.at(\stringify).value(value));
    });
    ("{" ++ (out.join(",")) ++ "}");
  },
  Nil, { arg obj;
    "null";
  },
  True, { arg obj;
    "true";
  },
  False, { arg obj;
    "false";
  },
  Number, { arg obj;
    if(obj.isNaN, {
        "NaN"
    }, {
      if(obj === inf, {
          "Infinity"
      }, {
        if(obj === (-inf), {
            "-Infinity"
        }, {
          obj.asString;
        });
      });
    });
  },
  SequenceableCollection, { arg obj;
    "[" ++ obj.collect({ arg sub;
              toJSON.at(\stringify).value(sub)
            }).join(",")
        ++ "]";
  }
]);

"\nSUPERCOLLIDERJS-interpreter-loaded".postln;
