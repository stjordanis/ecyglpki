# epyglpki-solvers.pxi: Cython/Python interface for GLPK MILP programs

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


cdef char* name2chars(name) except NULL:
    if not isinstance(name, str):
        raise TypeError("Name must be a 'str'.")
    name = name.encode()
    if len(name) > 255:
        raise ValueError("Name must not exceed 255 bytes.")
    return name

cdef coeffscheck(coeffs):
    if not isinstance(coeffs, collections.abc.Mapping):
        raise TypeError("Coefficients must be passed in a Mapping, not " +
                        type(coeffs).__name__)
    if not all([isinstance(value, numbers.Real) for value in coeffs.values()]):
        raise TypeError("Coefficient values must be Real numbers.")


cdef class MILProgram:
    """Main problem object

    .. doctest:: MILProgram

        >>> p = MILProgram('Linear Program')
        >>> isinstance(p, MILProgram)
        True

    """

    cdef glpk.ProbObj* _problem
    cdef int _unique_ids
    cdef readonly Variables variables
    """The problem's variables, collected in a `.Variables` object"""
    cdef readonly Constraints constraints
    """The problem's constraints, collected in a `.Constraints` object"""
    cdef readonly Objective objective
    """The problem's objective object, an `.Objective`"""
    cdef readonly SimplexSolver simplex
    """The problem's interior point solver object, a `.SimplexSolver`"""
    cdef readonly IPointSolver ipoint
    """The problem's interior point solver object, an `.IPointSolver`"""
    cdef readonly IntOptSolver intopt
    """The problem's interior point solver object, an `.IntOptSolver`"""

    def __cinit__(self, name=None):
        self._problem = glpk.create_prob()
        glpk.create_index(self._problem)
        self._unique_ids = 0
        self.variables = Variables(self)
        self.constraints = Constraints(self)
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
            for col in range(1, 1+glpk.get_num_cols(problem)):
                program.variables._link()
            for row in range(1, 1+glpk.get_num_rows(problem)):
                program.constraints._link()
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
        elif format is 'CNFSAT':
            retcode = glpk.write_cnfsat(self._problem, name2chars(fname))
        else:
            raise ValueError("Only 'GLPK', 'LP', 'MPS', and 'CNFSAT' " +
                             "formats are supported, not '" + format + "'.")
        if retcode is not 0:
            raise RuntimeError("Error writing " + format + " file.")

    def __dealloc__(self):
        glpk.delete_prob(self._problem)

    def _from_varstraintind(self, ind):
        n = len(self.constraints)
        if ind > n:
            return self.variables._from_ind(ind-n)
        else:
            return self.constraints._from_ind(ind)

    def _generate_alias(self):
        """Generate an alias to be used as a unique identifier

        It is useful to have a unique identifier for every Variable and
        Constraint. We use strings so that we can also use them as Variable or
        Constraint name if no name is given. The reason is that then we can
        rely on GLPK's name index and do not need to keep track of indices. To
        limit the possibility that a user chooses a name that could also be an
        alias, we use the format 'ŉ' + some integer value. The unicode
        character 'ŉ' was chosen specifically because it is deprecated (but
        will not be removed from the tables). The integer value is unique for
        the lifetime of the MILProgram object.

        """
        self._unique_ids += 1
        return 'ŉ' + str(self._unique_ids)

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
            cdef const char* chars = glpk.get_prob_name(self._problem)
            return '' if chars is NULL else chars.decode()
        def __set__(self, name):
            glpk.set_prob_name(self._problem, name2chars(name))
        def __del__(self):
            glpk.set_prob_name(self._problem, NULL)

    property coeffs:
        """Nonzero coefficients, a |Mapping| of (`.Constraint`, `.Variable`) to |Real|

        .. doctest:: MILProgram.coeffs

            >>> p = MILProgram()
            >>> x = p.variables.add()
            >>> y = p.variables.add()
            >>> c = p.constraints.add()
            >>> d = p.constraints.add()
            >>> p.coeffs = {(c, x): 3, (d, y): 5.5, (d, x): 0}
            >>> x.coeffs[c] == c.coeffs[x] == 3
            True
            >>> y.coeffs[d] == d.coeffs[y] == 5.5
            True
            >>> len(x.coeffs) is len(d.coeffs) is 1
            True
            >>> del p.coeffs
            >>> len(x.coeffs) is len(d.coeffs) is 0
            True

        .. note::

            This attribute cannot be read out directly, but only through
            `.Variable.coeffs` and `.Constraint.coeffs` methods.

        """
        def __set__(self, coeffs):
            coeffscheck(coeffs)
            if not all(isinstance(key, tuple) and (len(key) is 2)
                       for key in coeffs.keys()):
                raise TypeError("Coefficient keys must be pairs, " +
                                "i.e., length-2 tuples.")
            k = len(coeffs)
            cdef int* rows = <int*>glpk.alloc(1+k, sizeof(int))
            cdef int* cols = <int*>glpk.alloc(1+k, sizeof(int))
            cdef double* vals = <double*>glpk.alloc(1+k, sizeof(double))
            try:
                for i, item in enumerate(coeffs.items(), start=1):
                    if isinstance(item[0][0], Constraint):
                        row = item[0][0]._ind
                    else:  #  assume name
                        row = self.constraints._find_ind(item[0][0])
                    rows[i] = row
                    if isinstance(item[0][1], Variable):
                        col = item[0][1]._ind
                    else:  #  assume name
                        col = self.variables._find_ind(item[0][1])
                    cols[i] = col
                    vals[i] = item[1]
                glpk.load_matrix(self._problem, k, rows, cols, vals)
            finally:
                glpk.free(rows)
                glpk.free(cols)
                glpk.free(vals)
        def __del__(self):
            glpk.load_matrix(self._problem, 0, NULL, NULL, NULL)

    def scale(self, *algorithms):
        """Apply scaling algorithms or reset scaling

        :param algorithms: choose scaling algorithms to apply from among

            * `'auto'`: choose algorithms automatically
              (other arguments are ignored)
            * `'skip'`: skip scaling if the problem is already well-scaled
            * `'geometric'`: perform geometric mean scaling
            * `'equilibration'`: perform equilibration scaling
            * `'round'`: round scaling factors to the nearest power of two

            If no algorithm is given, the scaling is reset to the default
            values.

        :type algorithms: zero or more `str` arguments

        .. doctest:: MILProgram.scale

            >>> p = MILProgram()
            >>> x = p.variables.add()
            >>> y = p.variables.add()
            >>> c = p.constraints.add()
            >>> d = p.constraints.add()
            >>> p.coeffs = {(c, x): 3e-100, (d, y): 5.5, (d, x): 1.5e200}
            >>> x.scale, y.scale, c.scale, d.scale  # the GLPK default
            (1.0, 1.0, 1.0, 1.0)
            >>> p.scale('skip', 'geometric', 'round')
            >>> x.scale, y.scale, c.scale, d.scale
            (2.967...e-67, 1.135...e+133, 7.371...e+165, 2.201...e-134)
            >>> p.scale()
            >>> x.scale, y.scale, c.scale, d.scale
            (1.0, 1.0, 1.0, 1.0)

        """
        if len(algorithms) is 0:
            glpk.unscale_prob(self._problem)
        elif 'auto' in algorithms:
            glpk.scale_prob(self._problem, str2scalopt['auto'])
        else:
            glpk.scale_prob(self._problem, sum(str2scalopt[algorithm]
                                               for algorithm in algorithms))


cdef class _Component:

    cdef MILProgram _program
    cdef glpk.ProbObj* _problem

    def __cinit__(self, program):
        self._program = program
        self._problem = <glpk.ProbObj*>PyCapsule_GetPointer(
                                                program._problem_ptr(), NULL)
