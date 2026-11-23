import StudentProfilePage from './StudentProfilePage.jsx'

export default function MyWorkoutsPage({personal=false, bodyWeight=false, evolution=false}) {
  return <StudentProfilePage studentView personal={personal} bodyWeight={bodyWeight} evolution={evolution}/>
}
