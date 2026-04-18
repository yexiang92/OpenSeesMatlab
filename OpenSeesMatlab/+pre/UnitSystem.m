classdef UnitSystem < handle
    % Fast unit conversion system for OpenSeesMatlab.
    %
    % The unit system allows users to set their preferred basic units for length, force, and time. It then provides conversion factors for a wide range of units based on these basic units. Users can access unit conversion factors through properties (e.g., ``unit.mm``, ``unit.kN``, ``unit.MPa``) or by using the unit system as a function with an expression (e.g., ``unit("N/mm^2")``). ``unit.mm2`` would return the conversion factor for ``mm^2`` based on the current length unit, ``unit.mm3`` would return the conversion factor for ``mm^3`` based on the current length unit, and so on.
    % 
    % Supported units include:
    %
    % - lengthUnit, options: inch, ft, mm, cm, m, km
    % - forceUnit, options: lb, lbf, kip, n, kn, mn, kgf, tonf
    % - timeUnit, options: msec, sec, min, hour, day, year
    % - massUnit, options: mg, g, kg, ton, t, slug, slinch
    % - stressUnit, options: pa, kpa, mpa, gpa, bar, psi, ksi, psf, ksf
    %
    % Example
    % ---------
    %     unit = pre.unitSystem;
    %     unit.setBasicUnits(lengthUnit, forceUnit, timeUnit);
    %     a = unit.mm;
    %     b = unit.kN;
    %     c = unit.MPa;
    %     d = unit.mm2;
    %     e = unit("N/mm^2");

    properties (SetAccess = private)
        lengthUnit (1,1) string = "m"
        forceUnit  (1,1) string = "kn"
        timeUnit   (1,1) string = "sec"
    end

    properties (Access = private)
        values   % base unit name -> factor
        cache    % parsed expr/name -> factor
    end

    properties (Constant, Access = private)
        LENGTH_UNITS = {'inch','ft','mm','cm','m','km'}
        FORCE_UNITS  = {'lb','lbf','kip','n','kn','mn','kgf','tonf'}
        TIME_UNITS   = {'msec','sec','min','hour','day','year'}
        MASS_UNITS   = {'mg','g','kg','ton','t','slug','slinch'}
        STRESS_UNITS = {'pa','kpa','mpa','gpa','bar','psi','ksi','psf','ksf'}
    end

    methods
        function obj = UnitSystem()
            obj.values = pre.UnitSystem.createDoubleMap();
            obj.cache = pre.UnitSystem.createDoubleMap();
            obj.reset(obj.lengthUnit, obj.forceUnit, obj.timeUnit);
        end

        function setBasicUnits(obj, lengthUnit, forceUnit, timeUnit)
            % Set the basic units for length, force, and time. This will reset the unit system and update all conversion factors accordingly.
            %
            % Parameters
            % ----------
            % lengthUnit: string, default "m"
   ,         %   one of "inch", "ft", "mm", "cm", "m", "km"
            % forceUnit: string, default "kn"
            %   one of "lb", "lbf", "kip", "n", "kn", "mn", "kgf", "tonf"
            % timeUnit: string, default "sec"
            %   one of "msec", "sec", "min", "hour", "day", "year"
            if nargin < 2 || isempty(lengthUnit), lengthUnit = "m"; end
            if nargin < 3 || isempty(forceUnit),  forceUnit  = "kN"; end
            if nargin < 4 || isempty(timeUnit),   timeUnit   = "sec"; end
            obj.reset(lengthUnit, forceUnit, timeUnit);
        end

        function reset(obj, lengthUnit, forceUnit, timeUnit)
            if isempty(obj.values) || ~isa(obj.values, 'containers.Map')
                obj.values = pre.UnitSystem.createDoubleMap();
            end

            if isempty(obj.cache) || ~isa(obj.cache, 'containers.Map')
                obj.cache = pre.UnitSystem.createDoubleMap();
            end

            obj.lengthUnit = lower(string(lengthUnit));
            obj.forceUnit  = lower(string(forceUnit));
            obj.timeUnit   = lower(string(timeUnit));

            valueKeys = obj.values.keys;
            if ~isempty(valueKeys)
                remove(obj.values, valueKeys);
            end

            cacheKeys = obj.cache.keys;
            if ~isempty(cacheKeys)
                remove(obj.cache, cacheKeys);
            end

            obj.initValues();
        end

        function val = get(obj, expr)
            expr = char(strtrim(string(expr)));
            cacheKey = lower(expr);
            if isKey(obj.cache, cacheKey)
                val = obj.cache(cacheKey);
                return;
            end
            val = obj.parseExpr(expr);
            obj.cache(cacheKey) = val;
        end

        function disp(obj)
            fprintf('<UnitSystem: length="%s", force="%s", time="%s">\n', ...
                obj.lengthUnit, obj.forceUnit, obj.timeUnit);
        end

        function print(obj)
            fprintf('\nLength units:\n');
            obj.printGroup(obj.LENGTH_UNITS);

            fprintf('\nForce units:\n');
            obj.printGroup(obj.FORCE_UNITS);

            fprintf('\nTime units:\n');
            obj.printGroup(obj.TIME_UNITS);

            fprintf('\nMass units:\n');
            obj.printGroup(obj.MASS_UNITS);

            fprintf('\nStress units:\n');
            obj.printGroup(obj.STRESS_UNITS);
        end

        function varargout = subsref(obj, S)
            s1 = S(1);

            if strcmp(s1.type, '()')
                if numel(s1.subs) ~= 1
                    error('UnitSystem:InvalidCall', ...
                        'Use unit("expr") with exactly one input.');
                end
                out = obj.get(s1.subs{1});
                if numel(S) > 1
                    out = builtin('subsref', out, S(2:end));
                end
                if nargout > 1
                    error('UnitSystem:TooManyOutputs', ...
                        'Unit expressions support only a single output.');
                end
                if nargout > 0
                    varargout{1} = out;
                end
                return;
            end

            if strcmp(s1.type, '.')
                rawName = char(s1.subs);
                name = obj.resolveMemberName(rawName);
                isMember = ~strcmp(rawName, name) || pre.UnitSystem.isExactMemberName(rawName);

                % Fast path: real properties / methods
                if isMember
                    S(1).subs = name;
                    if nargout > 0
                        [varargout{1:nargout}] = builtin('subsref', obj, S);
                    else
                        builtin('subsref', obj, S);
                    end
                    return;
                end

                % Dynamic unit access
                val = obj.getUnitNameValue(name);
                if numel(S) > 1
                    val = builtin('subsref', val, S(2:end));
                end
                if nargout > 1
                    error('UnitSystem:TooManyOutputs', ...
                        'Dynamic unit access supports only a single output.');
                end
                if nargout > 0
                    varargout{1} = val;
                else
                    disp(val);
                end
                return;
            end

            if nargout > 0
                [varargout{1:nargout}] = builtin('subsref', obj, S);
            else
                builtin('subsref', obj, S);
            end
        end
    end

    methods (Access = private)
        function printGroup(obj, units)
            for i = 1:numel(units)
                u = units{i};
                fprintf('%s = %.12g\n', u, obj.values(lower(u)));
            end
        end

        function initValues(obj)
            ratioLength = obj.buildLengthRatios();
            ratioForce  = obj.buildForceRatios();
            ratioTime   = obj.buildTimeRatios();

            % base dimensions
            for i = 1:numel(obj.LENGTH_UNITS)
                u = obj.LENGTH_UNITS{i};
                key = [u '2' char(obj.lengthUnit)];
                obj.values(u) = ratioLength(key);
            end

            for i = 1:numel(obj.FORCE_UNITS)
                u = obj.FORCE_UNITS{i};
                key = [u '2' char(obj.forceUnit)];
                obj.values(u) = ratioForce(key);
            end

            for i = 1:numel(obj.TIME_UNITS)
                u = obj.TIME_UNITS{i};
                key = [u '2' char(obj.timeUnit)];
                obj.values(u) = ratioTime(key);
            end

            % aliases
            obj.values('s') = obj.values('sec');
            obj.values('ms') = obj.values('msec');
            obj.values('kips') = obj.values('kip');

            % mass
            kg = obj.values('n') * obj.values('sec')^2 / obj.values('m');
            obj.values('mg') = 1e-6 * kg;
            obj.values('g') = 1e-3 * kg;
            obj.values('kg') = kg;
            obj.values('ton') = 1e3 * kg;
            obj.values('t') = 1e3 * kg;
            obj.values('slug') = 14.593902937 * kg;
            obj.values('slinch') = 175.126836 * kg;

            % stress
            pa = obj.values('n') / obj.values('m')^2;
            obj.values('pa')  = pa;
            obj.values('kpa') = 1e3 * pa;
            obj.values('mpa') = 1e6 * pa;
            obj.values('gpa') = 1e9 * pa;
            obj.values('bar') = 1e5 * pa;
            obj.values('psi') = 6894.757293168 * pa;
            obj.values('ksi') = 6894757.293168 * pa;
            obj.values('psf') = 47.88025898033584 * pa;
            obj.values('ksf') = 47880.25898033584 * pa;

            % gravity
            obj.values('g0') = 9.80665 * obj.values('m') / obj.values('sec')^2;
            obj.values('grav') = obj.values('g0');
        end

        function val = getUnitNameValue(obj, name)
            % Handles:
            %   mm, kN, MPa, mm2, kN2, m3
            raw = char(name);
            cacheKey = lower(raw);
            if isKey(obj.cache, cacheKey)
                val = obj.cache(cacheKey);
                return;
            end

            clean = lower(regexprep(raw, '[^a-zA-Z0-9]', ''));

            % split trailing integer exponent
            n = length(clean);
            idx = n;
            while idx >= 1 && clean(idx) >= '0' && clean(idx) <= '9'
                idx = idx - 1;
            end

            base = clean(1:idx);
            if idx < n
                expStr = clean(idx+1:n);
                power = str2double(expStr);
            else
                power = 1;
            end

            if isempty(base) || ~isKey(obj.values, base)
                error('UnitSystem:UnknownUnit', 'Unknown unit "%s".', raw);
            end

            val = obj.values(base)^power;

            obj.cache(cacheKey) = val;
        end

        function name = resolveMemberName(~, name)
            memberMap = pre.UnitSystem.getMemberNameMap();
            key = lower(char(name));
            if isKey(memberMap, key)
                name = memberMap(key);
                return;
            end

            name = char(name);
        end

        function val = parseExpr(obj, expr)
            expr = regexprep(char(expr), '\s+', '');
            n = length(expr);
            if n == 0
                error('UnitSystem:EmptyExpression', 'Expression cannot be empty.');
            end

            total = 1.0;
            pos = 1;
            op = '*';

            while pos <= n
                c = expr(pos);
                if c == '*' || c == '/'
                    op = c;
                    pos = pos + 1;
                end

                startPos = pos;
                while pos <= n && isletter(expr(pos))
                    pos = pos + 1;
                end
                if pos == startPos
                    error('UnitSystem:ParseError', ...
                        'Bad unit token near "%s" in "%s".', expr(startPos:end), expr);
                end

                unit = lower(expr(startPos:pos-1));

                power = 1;
                if pos <= n
                    if expr(pos) == '^'
                        pos = pos + 1;
                        pStart = pos;
                        if pos <= n && (expr(pos) == '+' || expr(pos) == '-')
                            pos = pos + 1;
                        end
                        while pos <= n && isstrprop(expr(pos), 'digit')
                            pos = pos + 1;
                        end
                        if pStart == pos
                            error('UnitSystem:ParseError', ...
                                'Invalid exponent near "%s" in "%s".', expr(pStart:end), expr);
                        end
                        power = str2double(expr(pStart:pos-1));
                    else
                        pStart = pos;
                        while pos <= n && isstrprop(expr(pos), 'digit')
                            pos = pos + 1;
                        end
                        if pos > pStart
                            power = str2double(expr(pStart:pos-1));
                        end
                    end
                end

                if ~isKey(obj.values, unit)
                    error('UnitSystem:UnknownUnit', ...
                        'Unknown unit "%s" in "%s".', unit, expr);
                end

                factor = obj.values(unit)^power;

                if op == '*'
                    total = total * factor;
                else
                    total = total / factor;
                end
            end

            val = total;
        end
    end

    methods (Static, Access = private)
        function M = createDoubleMap()
            M = containers.Map('KeyType','char','ValueType','double');
        end

        function tf = isExactMemberName(name)
            memberMap = pre.UnitSystem.getMemberNameMap();
            key = lower(char(name));
            tf = isKey(memberMap, key);
        end

        function memberMap = getMemberNameMap()
            persistent cachedMemberMap

            if isempty(cachedMemberMap)
                cachedMemberMap = containers.Map('KeyType','char','ValueType','char');

                metaClass = ?pre.UnitSystem;

                propList = metaClass.PropertyList;
                for i = 1:numel(propList)
                    name = propList(i).Name;
                    cachedMemberMap(lower(name)) = name;
                end

                methodList = metaClass.MethodList;
                for i = 1:numel(methodList)
                    name = methodList(i).Name;
                    cachedMemberMap(lower(name)) = name;
                end
            end

            memberMap = cachedMemberMap;
        end

        function M = buildLengthRatios()
            M = containers.Map('KeyType','char','ValueType','double');
            data = {
                'inch2m',   0.0254
                'inch2dm',  0.254
                'inch2cm',  2.54
                'inch2mm',  25.4
                'inch2km',  2.54e-5
                'inch2ft',  1/12
                'ft2mm',    304.8
                'ft2cm',    30.48
                'ft2dm',    3.048
                'ft2m',     0.3048
                'ft2km',    3.048e-4
                'mm2cm',    0.1
                'mm2dm',    0.01
                'mm2m',     0.001
                'mm2km',    1e-6
                'cm2dm',    0.1
                'cm2m',     0.01
                'cm2km',    1e-5
                'm2km',     1e-3
            };
            M = pre.UnitSystem.fillRatioMap(M, data);
        end

        function M = buildForceRatios()
            M = containers.Map('KeyType','char','ValueType','double');
            data = {
                'lb2lbf',   1.0
                'lb2kip',   0.001
                'lb2n',     4.4482216152605
                'lb2kn',    4.4482216152605e-3
                'lb2mn',    4.4482216152605e-6
                'lb2kgf',   0.45359237
                'lb2tonf',  0.00045359237
                'lbf2kip',  0.001
                'lbf2n',    4.4482216152605
                'lbf2kn',   4.4482216152605e-3
                'lbf2mn',   4.4482216152605e-6
                'lbf2kgf',  0.45359237
                'lbf2tonf', 0.00045359237
                'kip2n',    4448.2216152605
                'kip2kn',   4.4482216152605
                'kip2mn',   0.0044482216152605
                'kip2kgf',  453.59237
                'kip2tonf', 0.45359237
                'n2kn',     1e-3
                'n2mn',     1e-6
                'n2kgf',    0.101971621297793
                'n2tonf',   1.01971621297793e-4
                'kn2mn',    1e-3
                'kn2kgf',   101.971621297793
                'kn2tonf',  0.101971621297793
                'mn2kgf',   101971.621297793
                'mn2tonf',  101.971621297793
                'kgf2tonf', 0.001
            };
            M = pre.UnitSystem.fillRatioMap(M, data);
        end

        function M = buildTimeRatios()
            M = containers.Map('KeyType','char','ValueType','double');
            data = {
                'sec2msec', 1000
                'sec2min',  1/60
                'sec2hour', 1/3600
                'sec2day',  1/24/3600
                'sec2year', 1/365/24/3600
                'min2msec', 1000*60
                'min2hour', 1/60
                'min2day',  1/24/60
                'min2year', 1/365/24/60
                'hour2msec',60*60*1000
                'hour2day', 1/24
                'hour2year',1/365/24
                'day2msec', 24*60*60*1000
                'day2hour', 24
                'day2year', 1/365
                'year2msec',365*24*60*60*1000
            };
            M = pre.UnitSystem.fillRatioMap(M, data);
        end

        function M = fillRatioMap(M, data)
            for i = 1:size(data,1)
                M(data{i,1}) = data{i,2};
            end

            ks = M.keys;
            for i = 1:numel(ks)
                key = ks{i};
                val = M(key);
                idx = strfind(key, '2');
                idx = idx(1);

                lhs = key(1:idx-1);
                rhs = key(idx+1:end);

                k1 = [rhs '2' lhs];
                k2 = [lhs '2' lhs];
                k3 = [rhs '2' rhs];

                if ~isKey(M, k1), M(k1) = 1/val; end
                if ~isKey(M, k2), M(k2) = 1; end
                if ~isKey(M, k3), M(k3) = 1; end
            end
        end
    end
end