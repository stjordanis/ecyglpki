# epyglpki.pyx: Cython/Python interface for GLPK

###############################################################################
#
#  This code is part of epyglpki (a Cython/Python GLPK interface).
#
#  Copyright (C) 2014 Erik Quaeghebeur. All rights reserved.
#
#  epyglpki is free software: you can redistribute it and/or modify it under
#  the terms of the GNU General Public License as published by the Free
#  Software Foundation, either version 3 of the License, or (at your option)
#  any later version.
#
#  epyglpki is distributed in the hope that it will be useful, but WITHOUT ANY
#  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
#  FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
#  details.
#
#  You should have received a copy of the GNU General Public License
#  along with epyglpki. If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################


cimport glpk
from cpython.pycapsule cimport PyCapsule_New, PyCapsule_GetPointer
import numbers
import collections.abc

include 'glpk-constants.pxi'


def GLPK_version():
    return glpk.version().decode()


cdef char* name2chars(name) except NULL:
    cdef char* chars
    if not isinstance(name, str):
        raise TypeError("Name must be a 'str'.")
    else:
        name = name.encode()
        if len(name) > 255:
            raise ValueError("Name must not exceed 255 bytes.")
        chars = name
    return chars


cdef class MILProgram:
    """Main problem object

    .. doctest:: MILProgram

        >>> p = MILProgram('Linear Program')
        >>> isinstance(p, MILProgram)
        True

    """

    cdef glpk.ProbObj* _problem
    cdef int _unique_ids
    cdef list _variables
    cdef list _constraints
    cdef readonly Objective objective
    """The problem's objective object, an `.Objective`"""
    cdef readonly SimplexSolver simplex
    """The problem's interior point solver object, an `.SimplexSolver`"""
    cdef readonly IPointSolver ipoint
    """The problem's interior point solver object, an `.IPointSolver`"""
    cdef readonly IntOptSolver intopt
    """The problem's interior point solver object, an `.IntOptSolver`"""

    def __cinit__(self, name=None):
        self._problem = glpk.create_prob()
        glpk.create_index(self._problem)
        self._unique_ids = 0
        self._variables = []
        self._constraints = []
        self.objective = Objective(self)
        self.simplex = SimplexSolver(self)
        self.ipoint = IPointSolver(self)
        self.intopt = IntOptSolver(self)
        if name is not None:
            self.name = name

    def _problem_ptr(self):
        """Encapsulate the pointer to the problem object

        The problem object pointer `self._problem` cannot be passed as such as
        an argument to other functions. Therefore we encapsulate it in a
        capsule that can be passed. It has to be unencapsulated after
        reception.

        """
        return PyCapsule_New(self._problem, NULL, NULL)

    @classmethod
    def read(cls, fname, format='GLPK', mpsfmt='free'):
        """Read a problem from a file (class method)

        :param fname: the name of the file to read from
        :type fname: `str`
        :param format: the format of the file read from; either `'GLPK'`,
            `'LP'`, `'MPS'`, or `'CNFSAT'`
        :type format: `str`
        :param mpsfmt: MPS-subformat; either `'free'` or `'fixed'`
            (ignored when *format* is not `'MPS'`)
        :type mpsfmt: `str`
        :raises ValueError: if *format* is not `'GLPK'`, `'LP'`, `'MPS'`,
            or `'CNFSAT'`
        :raises RuntimeError: if an error occurred reading the file

        .. todo::

            Add doctest

        """
        cdef glpk.ProbObj* problem
        program = cls()
        problem = <glpk.ProbObj*>PyCapsule_GetPointer(
                                                program._problem_ptr(), NULL)
        if format is 'GLPK':
            retcode = glpk.read_prob(problem, 0, name2chars(fname))
        elif format is 'LP':
            retcode = glpk.read_lp(problem, NULL, name2chars(fname))
        elif format is 'MPS':
            retcode = glpk.read_mps(problem, str2mpsfmt[mpsfmt], NULL,
                                    name2chars(fname))
        elif format is 'CNFSAT':
            retcode = glpk.read_cnfsat(problem, name2chars(fname))
        else:
            raise ValueError("Only 'GLPK', 'LP', 'MPS', and 'CNFSAT' " +
                             "formats are supported.")
        if retcode is 0:
            for col in range(glpk.get_num_cols(problem)):
                variable = Variable(program)
                program._variables.append(variable)
            for row in range(glpk.get_num_rows(problem)):
                constraint = Constraint(program)
                program._constraints.append(constraint)
        else:
            raise RuntimeError("Error reading " + format + " file.")
        return program

    def write(self, fname, format='GLPK', mpsfmt='free'):
        """Write the problem to a file

        :param fname: the name of the file to write to
        :type fname: `str`
        :param format: the format of the file written to; either
            `'GLPK'`, `'LP'`, `'MPS'`, or `'CNFSAT'`
        :type format: `str`
        :param mpsfmt: MPS-subformat; either `'free'` or `'fixed'`
            (ignored when *format* is not `'MPS'`)
        :type mpsfmt: `str`
        :raises ValueError: if *format* is not `'GLPK'`, `'LP'`, `'MPS'`,
            or `'CNFSAT'`
        :raises RuntimeError: if an error occurred writing the file

        .. todo::

            Add doctest

        """
        if format is 'GLPK':
            retcode = glpk.write_prob(self._problem, 0, name2chars(fname))
        elif format is 'LP':
            retcode = glpk.write_lp(self._problem, NULL, name2chars(fname))
        elif format is 'MPS':
            retcode = glpk.write_mps(self._problem, str2mpsfmt[mpsfmt], NULL,
                                     name2chars(fname))
        if format is 'CNFSAT':
            retcode = glpk.write_cnfsat(self._problem, name2chars(fname))
        else:
            raise ValueError("Only 'GLPK', 'LP', 'MPS', and 'CNFSAT' " +
                             "formats are supported.")
        if retcode is not 0:
            raise RuntimeError("Error writing " + format + " file.")

    def __dealloc__(self):
        glpk.delete_prob(self._problem)

    def _generate_unique_id(self):
        self._unique_ids += 1
        return self._unique_ids

    def _generate_alias(self):
        self._unique_ids += 1
        return 'ŉ' + str(self._unique_ids)  # ŉ is used to prefix aliases

    property name:
        """The problem name, a `str` of ≤255 bytes UTF-8 encoded

        .. doctest:: MILProgram

            >>> p.name
            'Linear Program'
            >>> p.name = 'Programme Linéaire'
            >>> p.name
            'Programme Linéaire'
            >>> del p.name  # clear name
            >>> p.name
            ''

        """
        def __get__(self):
            cdef char* chars = glpk.get_prob_name(self._problem)
            return '' if chars is NULL else chars.decode()
        def __set__(self, name):
            glpk.set_prob_name(self._problem, name2chars(name))
        def __del__(self):
            glpk.set_prob_name(self._problem, NULL)

    def _col(self, variable, alternate=False):
        """Return the column index of a Variable"""
        try:
            col = 1 + self._variables.index(variable)
            if alternate: # GLPK sometimes indexes variables after constraints
                col += len(self._constraints)
            return col
                # GLPK indices start at 1
        except ValueError:
            raise IndexError("This is possibly a zombie; kill it using 'del'.")

    def _variable(self, col, alternate=False):
        """Return the Variable corresponding to a column index"""
        if alternate: # GLPK sometimes indexes variables after constraints
            rows = len(self._constraints)
            if col <= rows:
                raise IndexError("Alternate column index cannot be smaller " +
                                 "than total number of rows")
            else:
                col -= rows
        return None if col is 0 else self._variables[col-1]

    def _row(self, constraint):
        """Return the row index of a Constraint"""
        try:
            return 1 + self._constraints.index(constraint)
                # GLPK indices start at 1
        except ValueError:
            raise IndexError("This is possibly a zombie; kill it using 'del'.")

    def _constraint(self, row):
        """Return the Constraint corresponding to a row index"""
        return None if row is 0 else self._constraints[row-1]

    def _ind(self, varstraint, alternate=False):
        """Return the column/row index of a Variable/Constraint"""
        if isinstance(varstraint, Variable):
            return self._col(varstraint, alternate)
        elif isinstance(varstraint, Constraint):
            return self._row(varstraint)
        else:
            raise TypeError("No index available for this object type.")

    def _varstraint(self, ind):
        """Return the Variable/Constraint corresponding to an alternate index"""
        if ind > len(self._constraints):
            return self._variable(ind, alternate=True)
        else:
            return self._constraint(ind)

    def _del_varstraint(self, varstraint):
        """Remove a Variable or Constraint from the problem"""
        if isinstance(varstraint, Variable):
            self._variables.remove(varstraint)
        elif isinstance(varstraint, Constraint):
            self._constraints.remove(varstraint)
        else:
            raise TypeError("No index available for this object type.")

    def add_variable(self, coeffs={}, lower_bound=False, upper_bound=False,
                     kind=None, name=None):
        """Add and obtain new variable object

        :param coeffs: set variable coefficients; see `.Variable.coeffs`
        :param lower_bound: set variable lower bound;
            see `.Varstraint.bounds`, parameter *lower*
        :param upper_bound: set variable upper bound;
            see `.Varstraint.bounds`, parameter *upper*
        :param kind: set variable kind; see `.Variable.kind`
        :param name: set variable name; see `.Variable.name`
        :returns: variable object
        :rtype: `.Variable`

        .. doctest:: MILProgram.add_variable

            >>> p = MILProgram()
            >>> x = p.add_variable()
            >>> x
            <epyglpki.Variable object at 0x...>

        """
        variable = Variable(self)
        self._variables.append(variable)
        assert len(self._variables) is glpk.get_num_cols(self._problem)
        variable.coeffs(None if not coeffs else coeffs)
        variable.bounds(lower_bound, upper_bound)
        if kind is not None:
            variable.kind = kind
        if name is not None:
            variable.name = name
        return variable

    def variables(self):
        """A list of the problem's variables

        :returns: a list of the problem's variables
        :rtype: `list` of `.Variable`

        .. doctest:: MILProgram.variables

            >>> p = MILProgram()
            >>> x = p.add_variable()
            >>> p.variables()
            [<epyglpki.Variable object at 0x...>]
            >>> y = p.add_variable()
            >>> v = p.variables()
            >>> (x in v) and (y in v)
            True

        """
        return self._variables

    def add_constraint(self, coeffs={}, lower_bound=False, upper_bound=False,
                       name=None):
        """Add and obtain new constraint object

        :param coeffs: set constraint coefficients; see `.Constraint.coeffs`
        :param lower_bound: set constraint lower bound;
            see `.Varstraint.bounds`, parameter *lower*
        :param upper_bound: set constraint upper bound;
            see `.Varstraint.bounds`, parameter *upper*
        :param name: set constraint name; see `.Constraint.name`
        :returns: constraint object
        :rtype: `.Constraint`

        .. doctest:: MILProgram.add_constraint

            >>> p = MILProgram()
            >>> c = p.add_constraint()
            >>> c
            <epyglpki.Constraint object at 0x...>

        """
        constraint = Constraint(self)
        self._constraints.append(constraint)
        assert len(self._constraints) is glpk.get_num_rows(self._problem)
        constraint.coeffs(None if not coeffs else coeffs)
        constraint.bounds(lower_bound, upper_bound)
        if name is not None:
            constraint.name = name
        return constraint

    def constraints(self):
        """Return a list of the problem's constraints

        :returns: a list of the problem's constraints
        :rtype: `list` of `.Constraint`

        .. doctest:: MILProgram.constraints

            >>> p = MILProgram()
            >>> c = p.add_constraint()
            >>> p.constraints()
            [<epyglpki.Constraint object at 0x...>]
            >>> d = p.add_constraint()
            >>> w = p.constraints()
            >>> (c in w) and (d in w)
            True

        """
        return self._constraints

    def coeffs(self, coeffs):
        """Replace or retrieve coefficients (constraint matrix)

        :param coeffs: the mapping with the new coefficients
            (``{}`` to set all coefficients to 0)
        :type coeffs: |Mapping| of length-2 |Sequence|, containing one
            `.Variable` and one `.Constraint`, to |Real|
        :raises TypeError: if *coeffs* is not |Mapping|
        :raises TypeError: if a coefficient key component is not a pair of
              `.Variable` and `.Constraint`
        :raises TypeError: if a coefficient value is not |Real|
        :raises ValueError: if the coefficient key does not have two
              components

        .. doctest:: MILProgram.coeffs

            >>> p = MILProgram()
            >>> x = p.add_variable()
            >>> y = p.add_variable()
            >>> c = p.add_constraint()
            >>> d = p.add_constraint()
            >>> p.coeffs({(x, c): 3, (d, y): 5.5, (x, d): 0})
            >>> x.coeffs()[c] == c.coeffs()[x] == 3
            True
            >>> y.coeffs()[d] == d.coeffs()[y] == 5.5
            True
            >>> len(x.coeffs()) == len(d.coeffs()) == 1
            True

        """
        if isinstance(coeffs, collections.abc.Mapping):
            elements = len(coeffs)
        else:
            raise TypeError("Coefficients must be given using a " +
                            "collections.abc.Mapping.")
        cdef double* vals = <double*>glpk.alloc(1+elements, sizeof(double))
        cdef int* cols = <int*>glpk.alloc(1+elements, sizeof(int))
        cdef int* rows = <int*>glpk.alloc(1+elements, sizeof(int))
        try:
            if elements is 0:
                glpk.load_matrix(self._problem, elements, NULL, NULL, NULL)
            else:
                nz_elements = elements
                for ind, item in enumerate(coeffs.items(), start=1):
                    val = vals[ind] = item[1]
                    if not isinstance(val, numbers.Real):
                        raise TypeError("Coefficient values must be " +
                                        "'numbers.Real' instead of '" +
                                        type(val).__name__ + "'.")
                    elif val == 0.0:
                        nz_elements -= 1
                    if len(item[0]) is not 2:
                        raise ValueError("Coefficient key must have " +
                                         "exactly two components.")
                    elif (isinstance(item[0][0], Variable) and
                        isinstance(item[0][1], Constraint)):
                        cols[ind] = self._col(item[0][0])
                        rows[ind] = self._row(item[0][1])
                    elif (isinstance(item[0][0], Constraint) and
                            isinstance(item[0][1], Variable)):
                        rows[ind] = self._row(item[0][0])
                        cols[ind] = self._col(item[0][1])
                    else:
                        raise TypeError("Coefficient position components " +
                                        "must be one Variable and one " +
                                        "Constraint.")
                glpk.load_matrix(self._problem, elements, rows, cols, vals)
                assert nz_elements is glpk.get_num_nz(self._problem)
        finally:
            glpk.free(vals)
            glpk.free(cols)
            glpk.free(rows)

    def scaling(self, *algorithms, factors=None):
        """Change, apply and unapply scaling factors

        :param algorithms: choose scaling algorithms to apply from among

            * `'auto'`: choose algorithms automatically
              (other arguments are ignored)
            * `'skip'`: skip scaling if the problem is already well-scaled
            * `'geometric'`: perform geometric mean scaling
            * `'equilibration'`: perform equilibration scaling
            * `'round'`: round scaling factors to the nearest power of two

        :type algorithms: zero or more `str` arguments
        :param factors: the mapping with scaling factors to change
            (``{}`` to set all factors to 1; omit for retrieval only);
            values defined here have precedence over the ones generated by
            *algorithms*
        :type factors: |Mapping| of `.Varstraint` to |Real|
        :returns: the scaling factor mapping, which only contains non-1
            factors
        :rtype: `dict` of `.Varstraint` to `float`
        :raises TypeError: if *factors* is not |Mapping|
        :raises TypeError: if the scaling factors are not |Real|
        :raises TypeError: if a key in the scaling factor mapping is not
            `.Varstraint`

        .. doctest:: MILProgram.scaling

            >>> p = MILProgram()
            >>> x = p.add_variable()
            >>> y = p.add_variable()
            >>> c = p.add_constraint()
            >>> d = p.add_constraint()
            >>> p.coeffs({(x, c): 3e-100, (d, y): 5.5, (x, d): 1.5e200})
            >>> p.scaling()
            {}
            >>> p.scaling('skip', 'geometric', 'equilibration',
            ...           factors={y: 3}) # doctest: +NORMALIZE_WHITESPACE
            {<epyglpki.Variable object at 0x...>: 3.329...e-67,
             <epyglpki.Variable object at 0x...>: 3.0,
             <epyglpki.Constraint object at 0x...>: 1.001...e+166,
             <epyglpki.Constraint object at 0x...>: 2.002...e-134}
            >>> p.scaling(factors={})
            {}

        .. note::

            If a scaling algorithm is given, all factors are first set to 1:

            .. doctest:: MILProgram.scaling

                >>> p.scaling(factors={d: 5.5})
                {<epyglpki.Constraint object at 0x...>: 5.5}
                >>> p.scaling('round')
                {}

        """
        if algorithms:
            if 'auto' in algorithms:
                glpk.scale_prob(self._problem, str2scalopt['auto'])
            else:
                glpk.scale_prob(self._problem, sum(str2scalopt[algorithm]
                                                for algorithm in algorithms))
        if factors == {}:
            glpk.unscale_prob(self._problem)
        elif isinstance(factors, collections.abc.Mapping):
            for varstraint, factor in factors.items():
                if not isinstance(factor, numbers.Real):
                    raise TypeError("Scaling factors must be real numbers.")
                if isinstance(varstraint, Variable):
                    glpk.set_col_sf(self._problem, self._col(varstraint),
                                    factor)
                elif isinstance(varstraint, Constraint):
                    glpk.set_row_sf(self._problem, self._row(varstraint),
                                    factor)
                else:
                    raise TypeError("Only 'Variable' and 'Constraint' can " +
                                    "have a scaling factor.")
        elif factors is not None:
            raise TypeError("Factors must be given using a " +
                            "collections.abc.Mapping.")
        factors = {}
        for col, variable in enumerate(self._variables, start=1):
            factor = glpk.get_col_sf(self._problem, col)
            if factor != 1.0:
                factors[variable] = factor
        for row, constraint in enumerate(self._constraints, start=1):
            factor = glpk.get_row_sf(self._problem, row)
            if factor != 1.0:
                factors[constraint] = factor
        return factors


cdef class _Component:

    cdef MILProgram _program
    cdef glpk.ProbObj* _problem

    def __cinit__(self, program):
        self._program = program
        self._problem = <glpk.ProbObj*>PyCapsule_GetPointer(
                                                program._problem_ptr(), NULL)


include "epyglpki-components.pxi"


include "epyglpki-solvers.pxi"
